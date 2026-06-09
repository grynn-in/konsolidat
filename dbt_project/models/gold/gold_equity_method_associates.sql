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

with equity_entities as (
    select
        cg.consolidation_group,
        cg.data_area_id,
        cg.entity_name,
        cg.ownership_pct / 100.0 as ownership_pct,
        cg.reporting_currency
    from {{ ref('consolidation_groups') }} as cg
    where cg.consolidation_method = 'equity'
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
    inner join equity_entities as ee
        on tb.data_area_id = ee.data_area_id
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
