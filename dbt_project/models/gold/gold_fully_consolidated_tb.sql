{{
    config(
        materialized='table',
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# #154: a TABLE, rebuilt and swapped in on every run. It carries no
   scope_filter/period_filter of its own: its SELECT always reads every upstream
   row (konsolidat#124), so a scoped close re-derived it in full anyway. As
   delete+insert it only replaced the keys the SELECT produced, and a key that
   left it (an entity that stopped consolidating) kept its rows forever. #}

{# PRD-5 R4: Unified consolidated trial balance
   Unions: entity balances + IC eliminations + CTA + topside adjustments
   PRD-14: + Layer 5: equity method entries
   PRD-11/12: + Layer 6: acquisition/disposal adjustments
   konsolidat#316: + Layer 8: journal close (decided 14 Nov 2026 by Deepak Pai, option A;
   design note on #316, chosen under the 5 Nov 2026 standing rule) #}

{# Layer 1: Entity translated balances.
   konsol#159: gold_consolidated_trial_balance has one row per intercompany
   partner. This layer is per account, so it sums over the partners. Passed
   through row by row, gold_consolidated_ytd ran a separate running total
   per partner row (#175 review: 250 instead of 150). #}
with entity_balances as (
    select
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        main_account,
        account_name,
        {{ dim_select(trailing=true) }}
        reporting_currency,
        sum(group_amount) as amount,
        'entity' as adjustment_type,
        '' as journal_id
    from {{ ref('gold_consolidated_trial_balance') }}
    group by
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        main_account,
        account_name,
        {{ dim_group_by(trailing=true) }}
        reporting_currency
),

{# Layer 2: IC eliminations. Posted in full (IFRS 10.B86(c); konsol#117
   pair 2 K3), so every entry is an ic_elimination with no entity on its legs:
   the minority's share is the NCI line of the NCI movement schedule, not part
   of the elimination. #}
ic_elims as (
    select
        consolidation_group,
        '' as data_area_id,
        fiscal_year,
        fiscal_period,
        debit_account as main_account,
        'IC Elimination' as account_name,
        {{ dim_empty_strings(trailing=true) }}
        '' as reporting_currency,
        debit_elimination as amount,
        'ic_elimination' as adjustment_type,
        rule_id as journal_id
    from {{ ref('gold_ic_eliminations') }}

    union all

    select
        consolidation_group,
        '' as data_area_id,
        fiscal_year,
        fiscal_period,
        credit_account as main_account,
        'IC Elimination' as account_name,
        {{ dim_empty_strings(trailing=true) }}
        '' as reporting_currency,
        credit_elimination as amount,
        'ic_elimination' as adjustment_type,
        rule_id as journal_id
    from {{ ref('gold_ic_eliminations') }}
),

{# Layer 3: CTA entries #}
cta_entries as (
    select
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        main_account,
        'CTA' as account_name,
        {{ dim_empty_strings(trailing=true) }}
        reporting_currency,
        cta_amount as amount,
        'cta' as adjustment_type,
        '' as journal_id
    from {{ ref('gold_fx_revaluation') }}
),

{# Layer 4: Top-side adjustments.
   konsol#305 V03 (P6): summed to the grain assert_journal_grain_unique checks, like layer 6
   (konsolidat#198 J11/J13). Passed through unsummed, two topside lines on one account, entity
   and period (two journals, or a journal next to its konsol#305-D2-11 auto_reversal line) gave
   two rows here — and, downstream, two running totals in gold_consolidated_ytd instead of one.
   journal_id is not part of the grain (a second journal on the same account in the same period
   is one row), so it is reported with any(journal_id), mirroring layer 6. #}
topside as (
    select
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        main_account,
        any(description) as account_name,
        {{ dim_empty_strings(trailing=true) }}
        '' as reporting_currency,
        sum({{ cast_to_float64('net_amount') }}) as amount,
        adjustment_type,
        any(journal_id) as journal_id
    from {{ ref('gold_consolidation_adjustments') }}
    group by consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account,
             adjustment_type
),

{# Layer 5: Equity method entries (PRD-14) #}
equity_method as (
    select
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        main_account,
        account_name,
        {{ dim_empty_strings(trailing=true) }}
        reporting_currency,
        amount,
        'equity_method' as adjustment_type,
        journal_id
    from {{ ref('gold_equity_method_associates') }}
),

{# Layer 7: NCI attribution (konsol#117 pair 2 K2, konsolidat#204 (a)): the minority's
   share of a full-method subsidiary's result and CTA, one balanced journal per
   (group, entity, period). #}
nci_attribution as (
    select
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        main_account,
        account_name,
        {{ dim_empty_strings(trailing=true) }}
        reporting_currency,
        amount,
        adjustment_type,
        journal_id
    from {{ ref('gold_nci_attribution_journal') }}
),

{# Layer 6: Acquisition & disposal adjustments (PRD-11/12).
   #175 re-review F3: the pnl_proration rows are one per consolidated row,
   and gold_consolidated_trial_balance has a row per intercompany partner,
   so they are summed to the account grain here, like layer 1 (the
   proration rows inherit the dimensions of their source row, review F1; the
   partner is summed away). Otherwise
   gold_consolidated_ytd ran a separate running total per row.
   konsolidat#198: the goodwill and fair-value lines come from the balanced
   acquisition journal (gold_business_combination_journal, posted from the
   submitted Business Combination), not from gold_acquisition_adjustments,
   which keeps only the partial-period P&L adjustment (#171 2c: it follows
   the group's declared partial_period_treatment, and its balancing line sits
   on the retained-earnings account). Row J5: the monthly goodwill
   amortisation journal (gold_goodwill_amortisation_journal, empty unless the
   group's goodwill_treatment is 'Amortise') joins the layer. Row J6: the
   disposal journal (gold_business_disposal_journal, posted from the
   submitted Business Disposal: derecognition, goodwill, FVA, CTA recycling,
   NCI, proceeds, gain or loss) replaces gold_disposal_adjustments' one-sided
   'DISPOSAL' rows; that model is now empty.
   Row J11 (PR #203 review 7): the journals post several lines to one account
   in one period when the roles differ (the acquisition journal's
   opening_balance and equity_eliminated lines on the same equity account,
   the disposal journal's derecognised and proceeds lines on the same cash
   account), so each journal branch is SUMmed to the account grain
   (group, entity, year, period, account, adjustment_type, journal_id) like
   the proration branch: passed through line by line, gold_consolidated_ytd's
   ROWS window ran a separate running total per line (-687.5, then 0, instead
   of 0). account_role is a line attribute, not part of the grain, and stays
   in the journal models; assert_journal_grain_unique proves the grain.
   Row J13 (PR #203 second review 2): journal_id left the grain too. The YTD
   window partitions by (group, entity, year, account, adjustment_type,
   dimensions) and NOT by journal_id, so two journals of one entity on one
   account in one period (a second deal; an amortisation instalment is a
   different adjustment_type) were two rows under one running total again.
   Each branch now groups without journal_id and emits any(journal_id);
   assert_journal_grain_unique keys on the window's partition columns. #}
acquisition_disposal as (
    select
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        main_account,
        account_name,
        {{ dim_select(trailing=true) }}
        '' as reporting_currency,
        sum(adjustment_amount) as amount,
        adjustment_type,
        concat('ACQ_', data_area_id) as journal_id
    from {{ ref('gold_acquisition_adjustments') }}
    group by consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account,
             account_name, adjustment_type{{ dim_group_by(leading=true) }}

    union all

    select
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        main_account,
        any(account_name) as account_name,
        {{ dim_empty_strings(trailing=true) }}
        '' as reporting_currency,
        sum(adjustment_amount) as amount,
        adjustment_type,
        any(journal_id) as journal_id
    from {{ ref('gold_business_combination_journal') }}
    group by consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account,
             adjustment_type

    union all

    select
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        main_account,
        any(account_name) as account_name,
        {{ dim_empty_strings(trailing=true) }}
        '' as reporting_currency,
        sum(adjustment_amount) as amount,
        adjustment_type,
        any(journal_id) as journal_id
    from {{ ref('gold_goodwill_amortisation_journal') }}
    group by consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account,
             adjustment_type

    union all

    select
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        main_account,
        any(account_name) as account_name,
        {{ dim_empty_strings(trailing=true) }}
        '' as reporting_currency,
        sum(adjustment_amount) as amount,
        adjustment_type,
        any(journal_id) as journal_id
    from {{ ref('gold_business_disposal_journal') }}
    group by consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account,
             adjustment_type
),

{# Union of the posted layers (every layer except the close itself) #}
posted_layers as (
    select * from entity_balances
    union all
    select * from ic_elims
    union all
    select * from cta_entries
    union all
    select * from topside
    union all
    select * from equity_method
    union all
    select * from acquisition_disposal
    union all
    select * from nci_attribution
),

{# Layer 8: journal close (konsolidat#316, decided 14 Nov 2026 by Deepak Pai: option A, one
   journal_close layer in this model; rejected B, each journal closes its own lines, and C, close
   at report time). Design note on #316, chosen under the 5 Nov 2026 standing rule.
   In each fiscal year's Closing period (the first period_type = 'Closing' of the year in
   fiscal_periods, as silver_tb_movements finds it) the year's P&L of every journal layer not in
   journal_close_excluded_layers() (entity: the #259 close; ic_elimination: reverses its own P&L
   legs) moves into retained_earnings_account(). P&L = silver_main_accounts.is_pnl = 1, or a
   pseudo-account in journal_pnl_pseudo_accounts() (EQ_INCOME). Summed over the year's periods up
   to AND including the Closing period; postings after it are not closed (the year-end test names
   them). One negating line per (group, entity, year, account, dimensions) and one retained-earnings
   line per (group, entity, year, dimensions); no partner (this table has none). When the chart
   flags not exactly one retained-earnings account, nothing is posted:
   assert_retained_earnings_account_unique fails naming the group. Reads posted_layers, never this
   model, so there is no cycle. #}
journal_close_periods as (
    select fiscal_year, min(fiscal_period) as closing_period
    from {{ source('epm_staging', 'fiscal_periods') }}
    where period_type = 'Closing'
    group by fiscal_year
),

journal_close_source as (
    select
        l.consolidation_group as consolidation_group,
        l.data_area_id as data_area_id,
        l.fiscal_year as fiscal_year,
        c.closing_period as closing_period,
        l.main_account as main_account,
        {# aliased: dim_select(prefix=) leaves the column named `l.<dim>` #}
        {% for d in get_dimensions() -%}
        l.{{ d.name }} as {{ d.name }},
        {% endfor -%}
        l.amount as amount
    from posted_layers as l
    inner join journal_close_periods as c on c.fiscal_year = l.fiscal_year
    left join {{ ref('silver_main_accounts') }} as ma on ma.main_account_id = l.main_account
    where l.adjustment_type not in ({{ "'" ~ journal_close_excluded_layers() | join("','") ~ "'" }})
      and l.fiscal_period <= c.closing_period
      and (ma.is_pnl = 1
           or l.main_account in ({{ "'" ~ journal_pnl_pseudo_accounts() | join("','") ~ "'" }}))
),

journal_close as (
    select
        s.consolidation_group as consolidation_group,
        s.data_area_id as data_area_id,
        s.fiscal_year as fiscal_year,
        s.closing_period as fiscal_period,
        s.main_account as main_account,
        'Journal close' as account_name,
        {# aliased: dim_select(prefix=) leaves the column named `s.<dim>` #}
        {% for d in get_dimensions() -%}
        s.{{ d.name }} as {{ d.name }},
        {% endfor -%}
        '' as reporting_currency,
        -sum(s.amount) as amount,
        'journal_close' as adjustment_type,
        concat('JCLOSE_', s.consolidation_group, '_', toString(s.fiscal_year)) as journal_id
    from journal_close_source as s
    cross join {{ retained_earnings_account() }} as re
    where re.re_count = 1
    group by s.consolidation_group, s.data_area_id, s.fiscal_year, s.closing_period,
             s.main_account{{ dim_group_by(prefix='s.', leading=true) }}

    union all

    select
        s.consolidation_group as consolidation_group,
        s.data_area_id as data_area_id,
        s.fiscal_year as fiscal_year,
        s.closing_period as fiscal_period,
        any(re.retained_earnings_account) as main_account,
        'Journal close' as account_name,
        {# aliased: dim_select(prefix=) leaves the column named `s.<dim>` #}
        {% for d in get_dimensions() -%}
        s.{{ d.name }} as {{ d.name }},
        {% endfor -%}
        '' as reporting_currency,
        sum(s.amount) as amount,
        'journal_close' as adjustment_type,
        concat('JCLOSE_', s.consolidation_group, '_', toString(s.fiscal_year)) as journal_id
    from journal_close_source as s
    cross join {{ retained_earnings_account() }} as re
    where re.re_count = 1
    group by s.consolidation_group, s.data_area_id, s.fiscal_year,
             s.closing_period{{ dim_group_by(prefix='s.', leading=true) }}
),

{# Union all layers #}
all_layers as (
    select * from posted_layers
    union all
    select * from journal_close
)

select * from all_layers
