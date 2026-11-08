{{
    config(
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# PRD-14: Equity method for associates (20-50% ownership)
   - equity_income = net_income × ownership%, translated into the group's
     reporting currency at the period's governed Average rate
   - investment = opening_investment + equity_income - dividends
   - Generates a two-line journal per associate per period using the reserved
     pseudo-accounts EQ_INCOME (the share of profit) and EQ_INVEST (the
     investment movement), balanced by construction: EQ_INVEST is the
     negation of EQ_INCOME. (A declared-account version of the two
     pseudo-accounts is a separate decision.)

   Signs. net_income is sum(period_net_amount) over P&L accounts, debit minus
   credit, so a PROFIT is negative. The share of a profit is therefore a
   credit on EQ_INCOME (negative) and a debit on EQ_INVEST (positive); a loss
   is the reverse. Until 7 Nov 2026 both lines carried the same signed figure,
   so a profit of X posted -X twice (net -2X) into layer 5 of
   gold_fully_consolidated_tb, and assert_end_to_end_bs_balances failed for
   any group with an associate in every period it had a result.
   assert_equity_method_journal_balances pins the sum at zero.

   Currency. The associate's net income is in its own accounting currency
   (silver_entity_currencies, exactly as gold_consolidated_trial_balance reads
   it) and the journal is labelled with the GROUP's reporting_currency, so it
   is translated at the period's governed Average rate from
   epm_staging.group_exchange_rates (konsolidat#93: the one source of FX
   rates; the rate is used as published), 1.0 when the two currencies are the
   same. Until 7 Nov 2026 no rate was applied: a SEK figure was posted into a
   EUR group as if it were EUR. A Closing-type period has no rates of its own
   and is keyed on its year's last Regular period (rate_period_map(),
   konsolidat#199 row D9), the same rule the consolidated trial balance uses.

   A missing, duplicated or invalid Average rate stops the build (throwIf in
   `translated`, the model's convention since konsolidat#93), never a 0 or a
   1.0 translation. It is NOT covered by gold_consolidated_trial_balance's
   pre_hook guard or by assert_every_translated_currency_has_a_governed_rate:
   governed_translated_keys() excludes equity-method entities on purpose
   (they are not line-consolidated), so for an associate this throwIf is the
   only stop. ClickHouse's throwIf takes a constant message, so the stop
   names no key: assert_equity_associate_has_average_rate (konsolidat#279)
   is the sibling that lists every (group, associate, currencies, period,
   reason) the throwIf would fire on, built from the same inputs with the
   same rate_period_map() keying and never from this model, so it still
   runs when the build is refused. The two are one rule: change the keying
   or the reasons here and there together. A zero result is not translated
   and needs no rate: neither the throwIf nor the test looks at it.

   Before the rate check, `no_reporting_currency` refuses the build when an
   associate's group has no root row in epm_gold.consolidation_groups
   (data_area_id = '') or its reporting_currency is blank: under
   join_use_nulls=0 the root-row miss reads reporting_currency = '', and
   the rate throwIf would then fire with an "approve the rate" message for
   what is a Consolidation Group defect. Its message names the keys (the
   cast-to-UInt8 trick governed_rate_guard() uses), and the test labels the
   same rows `no_reporting_currency`, never `missing`.

   Year-end close rows (konsolidat#279 defect 3). The result of a period is the
   associate's own activity in it. The year-end close silver_tb_movements
   synthesizes in a Closing period (konsolidat#259) moves the year's P&L into
   retained earnings, so summed as "net income of P13" it posted an entry equal
   and opposite to the year's result. `entity_net_income` subtracts the P&L rows
   marked is_year_end_close = 1 in gold_trial_balance_by_partner (the marker
   gold_consolidated_trial_balance reads); the Closing period then carries the
   share of its own activity, or no journal when it has none.
   assert_equity_method_ignores_close_rows pins it. A close an ERP posts itself
   carries no mark and still reads as activity (assert_year_end_close_carries_no_cta
   names it). Fixed in the PR that closes #279.

   A translated share of 0.01 or less in group currency posts no journal
   (`equity_entries`, abs(equity_income_amount) > 0.01): the rounding
   threshold, so a result that rounds to nothing is not a two-line entry. #}

{# F2: ownership and method come from gold_entity_ownership — dated, chain
   multiplied, one row per ancestor group. This read the consolidation_groups
   seed, so an associate's share was a June CSV figure that could never change
   on a date, and an associate held through a sub-group was invisible to the
   parent group entirely. #}
with equity_entities as (
    select
        eo.consolidation_group as consolidation_group,
        eo.data_area_id as data_area_id,
        eo.fiscal_year as fiscal_year,
        eo.fiscal_period as fiscal_period,
        cg.entity_name as entity_name,
        eo.effective_ownership_pct as ownership_pct,
        grp.reporting_currency as reporting_currency
    from {{ ref('gold_entity_ownership') }} as eo
    left join {{ source('epm_gold', 'consolidation_groups') }} as cg
        on cg.consolidation_group = eo.consolidation_group
        and cg.data_area_id = eo.data_area_id
    left join {{ source('epm_gold', 'consolidation_groups') }} as grp
        on grp.consolidation_group = eo.consolidation_group
        and grp.data_area_id = ''
    where eo.consolidation_method = 'equity'
      and eo.has_complete_chain = 1
),

{# The P&L the synthesized year-end close moved, per entity and period
   (konsolidat#279 defect 3). Debit minus credit, like net_income. #}
close_pnl as (
    select
        bp.data_area_id as data_area_id,
        bp.fiscal_year as fiscal_year,
        bp.fiscal_period as fiscal_period,
        sum(bp.period_net_amount) as close_amount
    from {{ ref('gold_trial_balance_by_partner') }} as bp
    inner join {{ ref('silver_main_accounts') }} as bma
        on bp.main_account = bma.main_account_id
    where bma.is_pnl = 1
      and bp.is_year_end_close = 1
    group by bp.data_area_id, bp.fiscal_year, bp.fiscal_period
),

{# Net income per entity per period (P&L accounts only, year-end close rows
   excluded), in the associate's own accounting currency, with the period
   whose governed rate translates it. #}
entity_net_income as (
    select
        ee.consolidation_group as consolidation_group,
        tb.data_area_id as data_area_id,
        tb.fiscal_year as fiscal_year,
        tb.fiscal_period as fiscal_period,
        ee.reporting_currency as reporting_currency,
        ec.accounting_currency as accounting_currency,
        ee.ownership_pct as ownership_pct,
        {# konsolidat#199 (row D9): the period whose governed rates this row
           translates at: itself, or its year's last Regular period for a
           Closing-type period. A period konsol's calendar does not know maps
           to itself (a LEFT JOIN miss reads mapped = 0 under join_use_nulls=0;
           the flag decides, never rate_period = 0, which an Opening period is
           legitimately numbered). #}
        if(rpm.mapped = 1, rpm.rate_year, toUInt16(tb.fiscal_year)) as rate_year,
        if(rpm.mapped = 1, rpm.rate_period, toUInt16(tb.fiscal_period)) as rate_period,
        {# join_use_nulls=0: no close row reads close_amount = 0 #}
        sum(tb.period_net_amount) - any(cl.close_amount) as net_income
    from {{ ref('gold_trial_balance') }} as tb
    {# period-keyed since F2: equity_entities is one row per entity PER PERIOD,
       so without it every period's net income would pair with every period's
       ownership row. #}
    inner join equity_entities as ee
        on tb.data_area_id = ee.data_area_id
        and tb.fiscal_year = ee.fiscal_year
        and tb.fiscal_period = ee.fiscal_period
    inner join {{ ref('silver_main_accounts') }} as ma
        on tb.main_account = ma.main_account_id
    {# Resolved currencies only, as gold_consolidated_trial_balance reads them:
       an associate with no Functional Currency has no rate key and is not
       posted; assert_every_tb_entity_has_a_currency names it. #}
    inner join (
        select data_area_id, accounting_currency
        from {{ ref('silver_entity_currencies') }}
        where accounting_currency != ''
    ) as ec
        on ec.data_area_id = tb.data_area_id
    left join {{ rate_period_map() }} as rpm
        on rpm.fiscal_year = tb.fiscal_year
        and rpm.fiscal_period = tb.fiscal_period
    left join close_pnl as cl
        on cl.data_area_id = tb.data_area_id
        and cl.fiscal_year = tb.fiscal_year
        and cl.fiscal_period = tb.fiscal_period
    where ma.is_pnl = 1
    group by ee.consolidation_group, tb.data_area_id, tb.fiscal_year, tb.fiscal_period,
             ee.reporting_currency, ec.accounting_currency, ee.ownership_pct,
             rate_year, rate_period
    {# A zero result is not translated (0 x any rate is 0), so it needs no
       rate: it is kept out here so the rate throwIf below and
       assert_equity_associate_has_average_rate look at the same rows. #}
    having sum(tb.period_net_amount) - any(cl.close_amount) != 0
),

{# konsolidat#279: a group with no root row in consolidation_groups
   (data_area_id = ''), or a root row with a blank reporting_currency, has no
   currency to translate INTO. The LEFT JOIN in equity_entities reads it as
   '' (join_use_nulls=0), and the rate throwIf would fire with an "approve
   the rate" message for a Consolidation Group defect. Refused here first,
   naming the keys: ClickHouse's throwIf needs a constant message, so, as
   governed_rate_guard() does, the message is CAST to UInt8 and the cast
   raises with the text. The inner query always returns one row; the outer
   WHERE keeps it only when there is something to refuse, so the CAST is
   never evaluated on a clean run. That holds only because concat reads the
   non-constant `n` and `keys`: make the message a pure literal and
   ClickHouse constant-folds the CAST at analysis time, behind the WHERE or
   not, and refuses every build (measured on 24.8: cast('X' as UInt8) under
   `where n > 0` throws with n = 0). `checked` reads it as a scalar subquery,
   which ClickHouse evaluates before any row of `translated`, so this stop
   comes before the rate one. assert_equity_associate_has_average_rate
   labels the same rows `no_reporting_currency`. #}
no_reporting_currency as (
    select cast(concat(
        'PRD-14 / konsolidat#279 refused: ', toString(n),
        ' equity-method associate period(s) whose group has no reporting currency to translate into',
        ' (no root row with data_area_id = '''' in epm_gold.consolidation_groups, or a blank reporting_currency): ', keys,
        if(n > 50, concat(' ... and ', toString(n - 50), ' more (assert_equity_associate_has_average_rate lists all)'), ''),
        '. Fix the Consolidation Group in konsol; this is not a missing rate.'
    ) as UInt8) as refused
    from (
        select
            count() as n,
            arrayStringConcat(arraySlice(arraySort(groupArray(
                concat(consolidation_group, '/', data_area_id, ' FY', toString(fiscal_year), ' P', toString(fiscal_period)))), 1, 50), '; ') as keys
        from entity_net_income
        where reporting_currency = ''
    )
    where n > 0
),

checked as (
    select *
    from entity_net_income
    where ifNull((select sum(refused) from no_reporting_currency), 0) = 0
),

{# One approved Average rate per key, as gold_consolidated_trial_balance's
   governed_rates CTE reads it: anyIf over no rows is 0, so presence is
   counted (n_average), never inferred from the value. `rate` is used exactly
   as published: the true rate, to_currency per 1 from_currency. #}
governed_average_rates as (
    select
        from_currency,
        to_currency,
        fiscal_year,
        fiscal_period,
        anyIf(toFloat64(rate), rate_type = 'Average') as gov_average,
        countIf(rate_type = 'Average') as n_average,
        countIf(rate_type = 'Average' and not (isFinite(rate) and rate > 0)) as n_invalid
    from {{ source('epm_staging', 'group_exchange_rates') }}
    group by from_currency, to_currency, fiscal_year, fiscal_period
),

{# The period's Average rate per associate row.
   join_use_nulls=0: a rate miss fills n_average = 0, so the count is the
   "no approved rate" signal (never a NULL test across the join). #}
translated as (
    select
        ni.consolidation_group as consolidation_group,
        ni.data_area_id as data_area_id,
        ni.fiscal_year as fiscal_year,
        ni.fiscal_period as fiscal_period,
        ni.reporting_currency as reporting_currency,
        ni.accounting_currency as accounting_currency,
        ni.ownership_pct as ownership_pct,
        ni.net_income as net_income,
        case
            {# A same-currency associate translates at 1 by definition, not a lookup. #}
            when ni.accounting_currency = ni.reporting_currency then 1.0
            when gr.n_average != 1 or gr.n_invalid > 0 then null
            else gr.gov_average
        end as average_rate
    from checked as ni
    left join governed_average_rates as gr
        on ni.accounting_currency = gr.from_currency
        and ni.reporting_currency = gr.to_currency
        and ni.rate_year = gr.fiscal_year
        and ni.rate_period = gr.fiscal_period
    {# A missing governed rate fails the build loudly, never a 0 or a 1.0
       translation. throwIf takes a per-row condition (a constant would be
       folded and raise on every build); ClickHouse needs a constant message,
       so the key is not in it. #}
    where throwIf(average_rate is null,
                  'PRD-14 / konsolidat#93: an equity-method associate''s accounting currency has no usable governed Average rate into its group''s reporting currency for its period (missing, duplicated, or zero, negative or not finite; a Closing period reads its year''s last Regular period). Approve it in konsol Group Exchange Rate. assert_equity_associate_has_average_rate (konsolidat#279) names every such key; assert_every_translated_currency_has_a_governed_rate does not list it: that covers line-consolidated entities only.') = 0
),

{# Equity income = net_income × ownership_pct × average rate, in the group's
   reporting currency. average_rate is Nullable (the CASE above has a null
   branch) and the throwIf has refused every null, so assumeNotNull keeps
   amount a plain Float64. #}
equity_income as (
    select
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        reporting_currency,
        ownership_pct,
        net_income,
        average_rate,
        net_income * ownership_pct * assumeNotNull(average_rate) as equity_income_amount
    from translated
),

{# Equity income entries (Dr EQ_INVEST, Cr EQ_INCOME) #}
equity_entries as (
    {# Income recognition: the share of the result, in the sign the trial
       balance carries it (a profit is a credit, negative). #}
    select
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        'EQ_INCOME' as main_account,
        'Equity method - share of profit' as account_name,
        reporting_currency,
        equity_income_amount as amount,
        'equity_method' as adjustment_type,
        {# consolidation_group is part of the key since F2: an associate held
           through a sub-group emits entries for the sub-group AND every
           ancestor above it, and without the group they shared one id. #}
        concat('EQ_', consolidation_group, '_', data_area_id, '_',
               toString(fiscal_year), '_P', toString(fiscal_period)) as journal_id
    from equity_income
    {# The posting threshold: a translated share of 0.01 or less in group
       currency is no journal. The data dictionary quotes this. #}
    where abs(equity_income_amount) > 0.01

    union all

    {# Investment movement: the counterpart, negated, so the journal sums to
       zero (assert_equity_method_journal_balances). Until 7 Nov 2026 this
       line carried equity_income_amount itself, the defect described above. #}
    select
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        'EQ_INVEST' as main_account,
        'Equity method - investment' as account_name,
        reporting_currency,
        -equity_income_amount as amount,
        'equity_method' as adjustment_type,
        {# consolidation_group is part of the key since F2: an associate held
           through a sub-group emits entries for the sub-group AND every
           ancestor above it, and without the group they shared one id. #}
        concat('EQ_', consolidation_group, '_', data_area_id, '_',
               toString(fiscal_year), '_P', toString(fiscal_period)) as journal_id
    from equity_income
    where abs(equity_income_amount) > 0.01
)

select * from equity_entries
