{{
    config(
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# PRD-14: Equity method for associates (20-50% ownership)
   - equity_income = net_income × ownership%
   - investment = opening_investment + equity_income - dividends
   - Generates single-line entries using reserved accounts EQ_INCOME, EQ_INVEST #}

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

{# Net income per entity per period (P&L accounts only) #}
entity_net_income as (
    select
        ee.consolidation_group as consolidation_group,
        tb.data_area_id as data_area_id,
        tb.fiscal_year as fiscal_year,
        tb.fiscal_period as fiscal_period,
        ee.reporting_currency as reporting_currency,
        ee.ownership_pct as ownership_pct,
        sum(tb.period_net_amount) as net_income
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
    where ma.is_pnl = 1
    group by ee.consolidation_group, tb.data_area_id, tb.fiscal_year, tb.fiscal_period,
             ee.reporting_currency, ee.ownership_pct
),

{# Equity income = net_income × ownership_pct #}
equity_income as (
    select
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        reporting_currency,
        ownership_pct,
        net_income,
        net_income * ownership_pct as equity_income_amount
    from entity_net_income
),

{# Equity income entries (Dr EQ_INVEST, Cr EQ_INCOME) #}
equity_entries as (
    {# Income recognition #}
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
        concat('EQ_', data_area_id, '_', toString(fiscal_year), '_P', toString(fiscal_period)) as journal_id
    from equity_income
    where abs(equity_income_amount) > 0.01

    union all

    {# Investment movement #}
    select
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        'EQ_INVEST' as main_account,
        'Equity method - investment' as account_name,
        reporting_currency,
        equity_income_amount as amount,
        'equity_method' as adjustment_type,
        concat('EQ_', data_area_id, '_', toString(fiscal_year), '_P', toString(fiscal_period)) as journal_id
    from equity_income
    where abs(equity_income_amount) > 0.01
)

select * from equity_entries
