{{
    config(
        materialized='table',
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# konsolidat#198 (design §4): the acquisition journal, posted from the deal
   documents konsol submits (epm_staging.business_combinations and its child
   tables; submit = approval, so every row here is a submitted deal). One
   journal per deal, `journal_id = ACQ-<group>-<entity>-<acquisition_date>`,
   in group currency, posted once in the acquisition period, and balanced by
   construction: the investment credit is the counterpart of every other line.
   assert_consolidation_journals_balance proves it per journal and period.

   Replaces gold_acquisition_adjustments' goodwill_entries and fva_entries,
   which were one-sided debits to the hardcoded accounts '1800'/'1900' and
   made assert_end_to_end_bs_balances (PRD-22) fail on every acquisition
   period. The accounts come from the group's root row in
   epm_gold.consolidation_groups (data_area_id = ''), declared in konsol: a
   deal whose group has no root row, or whose date is outside the declared
   calendar, posts nothing here (row J7's assert_acquisition_accounts_declared
   names it).

   Row J2 — the 100% case with an acquired-balances table:
     (1) equity_eliminated  each acquired-balance row whose account the chart
                            declares as equity (silver_main_accounts.is_equity):
                            -(book amount), so the credit balance konsol
                            recorded becomes a debit here (100%)
     (2) fva                Dr fair_value_adjustment_account by the sum of the
                            fair-value adjustments
     (3) goodwill           Dr goodwill_account by consideration - (net assets
                            + FVA); a negative figure is still posted here
                            until row J4 books it as a bargain purchase
     (4) investment         Cr investment_account by the consideration

   Net assets at acquisition = -(sum of the eliminated equity), the figure the
   equity lines carry, so the journal closes whatever the asset and liability
   rows of the acquired balance sheet sum to (measurement_basis
   'acquired_balances'). Rows J3 and J4 add lines (0) pre-acquisition
   history, (5) NCI, (3b) bargain gain and (6) costs.

   Currency: the consideration lines are translated from their own currency
   and the acquired balances from the entity's accounting currency
   (epm_staging.entities, konsol's registry) to the group's reporting
   currency at the acquisition period's governed Closing rate, the period
   mapped through rate_period_map() like every trial-balance translation. A
   line already in group currency translates at 1. When a deal has no
   consideration lines, the header's total_consideration (group currency, as
   konsol computed it) is used.

   Periods come from epm_staging.fiscal_periods by start_date <= date <=
   end_date, never from the month: a Closing period (one day inside the last
   Regular period) is skipped, so the deal lands in the Regular period.

   line_no: the child table's idx for the equity lines, then 101 fva,
   102 goodwill, 103 investment (104 nci, 105 bargain_gain, 110+ costs later). #}

with group_policy as (
    select
        consolidation_group,
        reporting_currency,
        nci_measurement,
        goodwill_treatment,
        acquisition_costs_treatment,
        bargain_purchase,
        goodwill_account,
        fair_value_adjustment_account,
        investment_account,
        nci_account,
        bargain_purchase_gain_account,
        disposal_proceeds_account,
        acquisition_costs_account
    from {{ source('epm_gold', 'consolidation_groups') }}
    where data_area_id = ''
),

{# the calendar period holding the acquisition date; the lowest-numbered
   non-Closing period whose span holds it. A range condition is not a
   ClickHouse join key, so the calendar is cross-joined and filtered. #}
deal_period as (
    select
        bc.name as deal,
        argMin(toUInt16(fp.fiscal_year), (toUInt16(fp.fiscal_year), toUInt16(fp.fiscal_period))) as fiscal_year,
        argMin(toUInt16(fp.fiscal_period), (toUInt16(fp.fiscal_year), toUInt16(fp.fiscal_period))) as fiscal_period
    from {{ source('epm_staging', 'business_combinations') }} as bc
    cross join {{ source('epm_staging', 'fiscal_periods') }} as fp
    where fp.start_date <= bc.acquisition_date
      and fp.end_date >= bc.acquisition_date
      and fp.period_type != 'Closing'
    group by bc.name
),

entity_currency as (
    select data_area_id, any(accounting_currency) as accounting_currency
    from {{ source('epm_staging', 'entities') }}
    group by data_area_id
),

deals as (
    select
        bc.name as deal,
        bc.consolidation_group as consolidation_group,
        bc.acquired_entity as data_area_id,
        bc.acquisition_date as acquisition_date,
        toFloat64(bc.share_acquired_pct) as share_acquired_pct,
        toFloat64(bc.total_consideration) as header_consideration,
        dp.fiscal_year as fiscal_year,
        dp.fiscal_period as fiscal_period,
        if(rpm.mapped = 1, rpm.rate_year, dp.fiscal_year) as rate_year,
        if(rpm.mapped = 1, rpm.rate_period, dp.fiscal_period) as rate_period,
        ec.accounting_currency as entity_currency,
        gp.reporting_currency as reporting_currency,
        gp.goodwill_account as goodwill_account,
        gp.fair_value_adjustment_account as fair_value_adjustment_account,
        gp.investment_account as investment_account,
        concat('ACQ-', bc.consolidation_group, '-', bc.acquired_entity, '-', toString(bc.acquisition_date)) as journal_id
    from {{ source('epm_staging', 'business_combinations') }} as bc
    inner join group_policy as gp
        on gp.consolidation_group = bc.consolidation_group
    inner join deal_period as dp
        on dp.deal = bc.name
    left join {{ rate_period_map() }} as rpm
        on rpm.fiscal_year = dp.fiscal_year
        and rpm.fiscal_period = dp.fiscal_period
    left join entity_currency as ec
        on ec.data_area_id = bc.acquired_entity
),

{# the governed Closing rate per (from, to, rate period); the same rows
   gold_consolidated_trial_balance translates at #}
closing_rates as (
    select
        from_currency,
        to_currency,
        toUInt16(fiscal_year) as fiscal_year,
        toUInt16(fiscal_period) as fiscal_period,
        any(toFloat64(rate)) as closing_rate
    from {{ source('epm_staging', 'group_exchange_rates') }}
    where rate_type = 'Closing'
    group by from_currency, to_currency, fiscal_year, fiscal_period
),

{# consideration in group currency: the lines translated at the closing rate,
   or the header figure when the deal has no lines #}
consideration_lines as (
    select
        d.deal as deal,
        count() as n_lines,
        sum(toFloat64(c.amount) * if(c.currency = d.reporting_currency, 1.0, cr.closing_rate)) as consideration
    from {{ source('epm_staging', 'business_combination_consideration') }} as c
    inner join deals as d
        on d.deal = c.parent
    left join closing_rates as cr
        on cr.from_currency = c.currency
        and cr.to_currency = d.reporting_currency
        and cr.fiscal_year = d.rate_year
        and cr.fiscal_period = d.rate_period
    group by d.deal
),

consideration as (
    select
        d.deal as deal,
        if(cl.n_lines > 0, cl.consideration, d.header_consideration) as consideration
    from deals as d
    left join consideration_lines as cl
        on cl.deal = d.deal
),

{# the acquired balance sheet konsol recorded, translated to group currency #}
acquired_balances as (
    select
        d.deal as deal,
        ab.idx as idx,
        ab.main_account as main_account,
        ma.account_name as account_name,
        ma.is_equity as is_equity,
        toFloat64(ab.book_amount) * if(d.entity_currency = d.reporting_currency, 1.0, cr.closing_rate) as book_amount,
        toFloat64(ab.fair_value_adjustment) * if(d.entity_currency = d.reporting_currency, 1.0, cr.closing_rate) as fair_value_adjustment
    from {{ source('epm_staging', 'business_combination_acquired_balances') }} as ab
    inner join deals as d
        on d.deal = ab.parent
    left join closing_rates as cr
        on cr.from_currency = d.entity_currency
        and cr.to_currency = d.reporting_currency
        and cr.fiscal_year = d.rate_year
        and cr.fiscal_period = d.rate_period
    left join {{ ref('silver_main_accounts') }} as ma
        on ma.main_account_id = ab.main_account
),

measured as (
    select
        deal,
        count() as n_balance_rows,
        -sumIf(book_amount, is_equity = 1) as net_assets,
        sum(fair_value_adjustment) as fva
    from acquired_balances
    group by deal
),

figures as (
    select
        d.deal as deal,
        d.consolidation_group as consolidation_group,
        d.data_area_id as data_area_id,
        d.fiscal_year as fiscal_year,
        d.fiscal_period as fiscal_period,
        d.acquisition_date as acquisition_date,
        d.journal_id as journal_id,
        d.goodwill_account as goodwill_account,
        d.fair_value_adjustment_account as fair_value_adjustment_account,
        d.investment_account as investment_account,
        c.consideration as consideration,
        m.net_assets as net_assets,
        m.fva as fva,
        c.consideration - (m.net_assets + m.fva) as goodwill,
        'acquired_balances' as measurement_basis
    from deals as d
    inner join consideration as c
        on c.deal = d.deal
    inner join measured as m
        on m.deal = d.deal
    where m.n_balance_rows > 0
),

{# chart names for the declared accounts; '' when the chart lacks the code #}
chart as (
    select main_account_id, any(account_name) as account_name
    from {{ ref('silver_main_accounts') }}
    group by main_account_id
),

equity_lines as (
    select
        f.deal as deal,
        f.consolidation_group as consolidation_group,
        f.data_area_id as data_area_id,
        f.fiscal_year as fiscal_year,
        f.fiscal_period as fiscal_period,
        ab.main_account as main_account,
        ab.account_name as account_name,
        -ab.book_amount as adjustment_amount,
        f.acquisition_date as acquisition_date,
        f.journal_id as journal_id,
        toUInt16(ab.idx) as line_no,
        'equity_eliminated' as account_role,
        f.measurement_basis as measurement_basis
    from acquired_balances as ab
    inner join figures as f
        on f.deal = ab.deal
    where ab.is_equity = 1
),

{# one row per fixed line of each deal; a zero line (no FVA, say) is left out #}
fixed_raw as (
    select
        deal,
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        acquisition_date,
        journal_id,
        measurement_basis,
        line_account,
        line_amount,
        line_no,
        account_role,
        default_name
    from figures
    array join
        [fair_value_adjustment_account, goodwill_account, investment_account] as line_account,
        [fva, goodwill, -consideration] as line_amount,
        [toUInt16(101), toUInt16(102), toUInt16(103)] as line_no,
        ['fva', 'goodwill', 'investment'] as account_role,
        ['Fair value adjustment on acquisition', 'Goodwill on acquisition', 'Investment in subsidiary eliminated'] as default_name
    where abs(line_amount) > 0.005
),

fixed_lines as (
    select
        l.deal as deal,
        l.consolidation_group as consolidation_group,
        l.data_area_id as data_area_id,
        l.fiscal_year as fiscal_year,
        l.fiscal_period as fiscal_period,
        l.line_account as main_account,
        if(ch.account_name != '', ch.account_name, l.default_name) as account_name,
        l.line_amount as adjustment_amount,
        l.acquisition_date as acquisition_date,
        l.journal_id as journal_id,
        l.line_no as line_no,
        l.account_role as account_role,
        l.measurement_basis as measurement_basis
    from fixed_raw as l
    left join chart as ch
        on ch.main_account_id = l.line_account
),

journal as (
    select * from equity_lines
    union all
    select * from fixed_lines
)

select
    consolidation_group,
    data_area_id,
    fiscal_year,
    toUInt8(fiscal_period) as fiscal_period,
    main_account,
    account_name,
    'acquisition' as adjustment_type,
    adjustment_amount,
    acquisition_date,
    journal_id,
    line_no,
    account_role,
    deal,
    measurement_basis
from journal
