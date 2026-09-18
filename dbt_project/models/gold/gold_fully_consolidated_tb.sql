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
   PRD-11/12: + Layer 6: acquisition/disposal adjustments #}

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

{# Layer 2: IC eliminations, the group view (gold_ic_eliminations also holds
   the NCI view's entries, which the consolidation report adds for its 100%
   column). The 'nci' entries (decision 12) are tagged ic_elimination_nci and
   carry the entity on each leg: the NCI line's leg is the partly owned
   entity whose minority holds that share (#175 re-review L2). The cash flow
   statement leaves out a balance-sheet pair's ones and keeps a P&L pair's
   (third review L1). #}
ic_elims as (
    select
        consolidation_group,
        if(elimination_kind = 'nci', debit_entity, '') as data_area_id,
        fiscal_year,
        fiscal_period,
        debit_account as main_account,
        'IC Elimination' as account_name,
        {{ dim_empty_strings(trailing=true) }}
        '' as reporting_currency,
        debit_elimination as amount,
        if(elimination_kind = 'nci', 'ic_elimination_nci', 'ic_elimination') as adjustment_type,
        rule_id as journal_id
    from {{ ref('gold_ic_eliminations') }}
    where elimination_view = 'group'

    union all

    select
        consolidation_group,
        if(elimination_kind = 'nci', credit_entity, '') as data_area_id,
        fiscal_year,
        fiscal_period,
        credit_account as main_account,
        'IC Elimination' as account_name,
        {{ dim_empty_strings(trailing=true) }}
        '' as reporting_currency,
        credit_elimination as amount,
        if(elimination_kind = 'nci', 'ic_elimination_nci', 'ic_elimination') as adjustment_type,
        rule_id as journal_id
    from {{ ref('gold_ic_eliminations') }}
    where elimination_view = 'group'
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

{# Layer 4: Top-side adjustments #}
topside as (
    select
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        main_account,
        description as account_name,
        {{ dim_empty_strings(trailing=true) }}
        '' as reporting_currency,
        {{ cast_to_float64('net_amount') }} as amount,
        adjustment_type,
        journal_id
    from {{ ref('gold_consolidation_adjustments') }}
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

{# Layer 6: Acquisition & disposal adjustments (PRD-11/12).
   #175 re-review F3: the pnl_proration rows are one per consolidated row,
   and gold_consolidated_trial_balance has a row per intercompany partner,
   so they are summed to the account grain here, like layer 1. Otherwise
   gold_consolidated_ytd ran a separate running total per row.
   konsolidat#198: the goodwill and fair-value lines come from the balanced
   acquisition journal (gold_business_combination_journal, posted from the
   submitted Business Combination), not from gold_acquisition_adjustments,
   which keeps only the P&L proration. Row J5: the monthly goodwill
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
        {{ dim_empty_strings(trailing=true) }}
        '' as reporting_currency,
        sum(adjustment_amount) as amount,
        adjustment_type,
        concat('ACQ_', data_area_id) as journal_id
    from {{ ref('gold_acquisition_adjustments') }}
    group by consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account,
             account_name, adjustment_type

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

{# Union all layers #}
all_layers as (
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
)

select * from all_layers
