{{
    config(
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# PRD-1: Proper FX translation — closing rate for BS, average rate for PnL
   PRD-4: Minority interest — nci_amount column for partial ownership #}

with entity_tb as (
    select
        tb.data_area_id as data_area_id,
        tb.fiscal_year as fiscal_year,
        tb.fiscal_period as fiscal_period,
        tb.main_account as main_account,
        tb.account_name as account_name,
        tb.account_type_name as account_type_name,
        tb.is_balance_sheet as is_balance_sheet,
        tb.is_pnl as is_pnl,
        {{ dim_select(prefix='tb.') }},
        tb.period_net_amount as local_amount,
        le.accounting_currency as accounting_currency,
        {{ build_date_from_year_period('tb.fiscal_year', 'tb.fiscal_period') }} as period_date
    from {{ ref('gold_trial_balance') }} as tb
    inner join {{ ref('silver_legal_entities') }} as le
        on tb.data_area_id = le.data_area
),

{# Distinct currency-pair × period combos we need rates for #}
rate_keys as (
    select distinct
        etb.accounting_currency as from_currency,
        cg.reporting_currency as to_currency,
        etb.period_date
    from entity_tb as etb
    inner join {{ ref('consolidation_groups') }} as cg
        on etb.data_area_id = cg.data_area_id
),

all_rates as (
    select
        from_currency,
        to_currency,
        valid_from,
        exchange_rate as rate,
        exchange_rate_type
    from {{ ref('silver_exchange_rates') }}
),

{# Best closing rate as-of each period_date (latest valid_from <= period_date) #}
closing_rate_lookup as (
    select
        rk.from_currency,
        rk.to_currency,
        rk.period_date,
        {{ latest_value_by('ar.rate', 'ar.valid_from') }} as rate
    from rate_keys as rk
    inner join all_rates as ar
        on rk.from_currency = ar.from_currency
        and rk.to_currency = ar.to_currency
    where ar.exchange_rate_type = 'Closing'
        and ar.valid_from <= rk.period_date
    group by rk.from_currency, rk.to_currency, rk.period_date
),

{# Best average rate as-of each period_date #}
average_rate_lookup as (
    select
        rk.from_currency,
        rk.to_currency,
        rk.period_date,
        {{ latest_value_by('ar.rate', 'ar.valid_from') }} as rate
    from rate_keys as rk
    inner join all_rates as ar
        on rk.from_currency = ar.from_currency
        and rk.to_currency = ar.to_currency
    where ar.exchange_rate_type = 'Average'
        and ar.valid_from <= rk.period_date
    group by rk.from_currency, rk.to_currency, rk.period_date
),

{# Default fallback rate #}
default_rate_lookup as (
    select
        rk.from_currency,
        rk.to_currency,
        rk.period_date,
        {{ latest_value_by('ar.rate', 'ar.valid_from') }} as rate
    from rate_keys as rk
    inner join all_rates as ar
        on rk.from_currency = ar.from_currency
        and rk.to_currency = ar.to_currency
    where ar.exchange_rate_type = ''
        and ar.valid_from <= rk.period_date
    group by rk.from_currency, rk.to_currency, rk.period_date
),

{# Merge into single lookup: closing with fallback, average with fallback #}
rate_lookup as (
    select
        rk.from_currency as from_currency,
        rk.to_currency as to_currency,
        rk.period_date as period_date,
        coalesce(cr.rate, dr.rate, 1.0) as closing_rate,
        coalesce(ar.rate, dr.rate, 1.0) as average_rate
    from rate_keys as rk
    left join closing_rate_lookup as cr
        on rk.from_currency = cr.from_currency
        and rk.to_currency = cr.to_currency
        and rk.period_date = cr.period_date
    left join average_rate_lookup as ar
        on rk.from_currency = ar.from_currency
        and rk.to_currency = ar.to_currency
        and rk.period_date = ar.period_date
    left join default_rate_lookup as dr
        on rk.from_currency = dr.from_currency
        and rk.to_currency = dr.to_currency
        and rk.period_date = dr.period_date
),

consolidated as (
    select
        cg.consolidation_group as consolidation_group,
        etb.data_area_id as data_area_id,
        etb.fiscal_year as fiscal_year,
        etb.fiscal_period as fiscal_period,
        etb.main_account as main_account,
        etb.account_name as account_name,
        etb.account_type_name as account_type_name,
        etb.is_balance_sheet as is_balance_sheet,
        etb.is_pnl as is_pnl,
        {{ dim_select(prefix='etb.') }},
        etb.local_amount as local_amount,
        etb.accounting_currency as accounting_currency,
        cg.reporting_currency as reporting_currency,
        cg.ownership_pct / 100.0 as ownership_pct,
        cg.consolidation_method as consolidation_method,
        rl.closing_rate as closing_rate,
        rl.average_rate as average_rate,
        {# PRD-1: Translation rate depends on account type #}
        case
            when etb.is_balance_sheet = 1 then rl.closing_rate
            when etb.is_pnl = 1 then rl.average_rate
            else rl.closing_rate
        end as translation_rate,
        {# Translated amount = local x translation_rate #}
        etb.local_amount * case
            when etb.is_balance_sheet = 1 then rl.closing_rate
            when etb.is_pnl = 1 then rl.average_rate
            else rl.closing_rate
        end as translated_amount,
        {# PRD-4: Group amount = translated x ownership_pct #}
        etb.local_amount * case
            when etb.is_balance_sheet = 1 then rl.closing_rate
            when etb.is_pnl = 1 then rl.average_rate
            else rl.closing_rate
        end * (cg.ownership_pct / 100.0) as group_amount,
        {# PRD-4: NCI amount = translated x (1 - ownership_pct) #}
        etb.local_amount * case
            when etb.is_balance_sheet = 1 then rl.closing_rate
            when etb.is_pnl = 1 then rl.average_rate
            else rl.closing_rate
        end * (1.0 - cg.ownership_pct / 100.0) as nci_amount
    from entity_tb as etb
    inner join {{ ref('consolidation_groups') }} as cg
        on etb.data_area_id = cg.data_area_id
    left join rate_lookup as rl
        on etb.accounting_currency = rl.from_currency
        and cg.reporting_currency = rl.to_currency
        and etb.period_date = rl.period_date
)

select * from consolidated
