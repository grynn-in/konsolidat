{{
    config(
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# PRD-1: Proper FX translation — closing rate for BS, average rate for PnL
   PRD-4: Minority interest — nci_amount column for partial ownership
   PRD-8: Multi-level hierarchy — effective_ownership from hierarchy or seed fallback
   PRD-9: Temporal ownership — period-level ownership from ownership_periods staging
   PRD-10: Historical equity rates — equity accounts use historical rate (IAS 21) #}

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
        {# PRD-10: Equity classification for historical rate lookup #}
        case when tb.account_type_name in ('Equity', 'Stockholders equity') then 1 else 0 end as is_equity,
        {{ dim_select(prefix='tb.') }},
        tb.period_net_amount as local_amount,
        le.accounting_currency as accounting_currency,
        {{ build_date_from_year_period('tb.fiscal_year', 'tb.fiscal_period') }} as period_date
    from {{ ref('gold_trial_balance') }} as tb
    inner join {{ ref('silver_legal_entities') }} as le
        on tb.data_area_id = le.data_area
),

{# PRD-9: Temporal ownership periods from staging — range lookup per entity per period #}
ownership_staging as (
    select
        consolidation_group,
        data_area_id,
        effective_date,
        end_date,
        ownership_pct,
        consolidation_method
    from {{ source('epm_staging', 'ownership_periods') }}
),

{# PRD-8: Hierarchy-based ownership — prefer hierarchy, fall back to seed #}
hierarchy_ownership as (
    select
        h.consolidation_group,
        h.data_area_id,
        h.effective_ownership_pct as hierarchy_ownership_pct
    from {{ ref('gold_consolidation_hierarchy') }} as h
),

{# Resolve ownership: temporal staging → hierarchy → seed fallback #}
entity_ownership as (
    select
        cg.consolidation_group as consolidation_group,
        cg.data_area_id as data_area_id,
        cg.reporting_currency as reporting_currency,
        cg.consolidation_method as seed_method,
        cg.ownership_pct as seed_ownership_pct,
        coalesce(ho.hierarchy_ownership_pct, cg.ownership_pct) as base_ownership_pct
    from {{ ref('consolidation_groups') }} as cg
    left join hierarchy_ownership as ho
        on cg.consolidation_group = ho.consolidation_group
        and cg.data_area_id = ho.data_area_id
),

{# PRD-10: Historical equity rates from staging #}
historical_rates as (
    select
        consolidation_group,
        data_area_id,
        main_account,
        rate_date,
        historical_rate
    from {{ source('epm_staging', 'historical_equity_rates') }}
),

{# Distinct currency-pair × period combos we need rates for #}
rate_keys as (
    select distinct
        etb.accounting_currency as from_currency,
        eo.reporting_currency as to_currency,
        etb.period_date
    from entity_tb as etb
    inner join entity_ownership as eo
        on etb.data_area_id = eo.data_area_id
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
        eo.consolidation_group as consolidation_group,
        etb.data_area_id as data_area_id,
        etb.fiscal_year as fiscal_year,
        etb.fiscal_period as fiscal_period,
        etb.main_account as main_account,
        etb.account_name as account_name,
        etb.account_type_name as account_type_name,
        etb.is_balance_sheet as is_balance_sheet,
        etb.is_pnl as is_pnl,
        etb.is_equity as is_equity,
        {{ dim_select(prefix='etb.') }},
        etb.local_amount as local_amount,
        etb.accounting_currency as accounting_currency,
        eo.reporting_currency as reporting_currency,
        {# PRD-9: Temporal ownership — use staging period match, else hierarchy/seed #}
        coalesce(
            os.ownership_pct,
            eo.base_ownership_pct
        ) / 100.0 as ownership_pct,
        coalesce(os.consolidation_method, eo.seed_method) as consolidation_method,
        rl.closing_rate as closing_rate,
        rl.average_rate as average_rate,
        {# PRD-10: Historical equity rate lookup #}
        hr.historical_rate as historical_equity_rate,
        {# PRD-1 + PRD-10: Translation rate depends on account type
           Equity → historical rate (fallback closing), BS → closing, PnL → average #}
        case
            when etb.is_equity = 1 and hr.historical_rate is not null then hr.historical_rate
            when etb.is_balance_sheet = 1 then rl.closing_rate
            when etb.is_pnl = 1 then rl.average_rate
            else rl.closing_rate
        end as translation_rate,
        {# Translated amount = local x translation_rate #}
        etb.local_amount * case
            when etb.is_equity = 1 and hr.historical_rate is not null then hr.historical_rate
            when etb.is_balance_sheet = 1 then rl.closing_rate
            when etb.is_pnl = 1 then rl.average_rate
            else rl.closing_rate
        end as translated_amount,
        {# PRD-4: Group amount = translated x ownership_pct #}
        etb.local_amount * case
            when etb.is_equity = 1 and hr.historical_rate is not null then hr.historical_rate
            when etb.is_balance_sheet = 1 then rl.closing_rate
            when etb.is_pnl = 1 then rl.average_rate
            else rl.closing_rate
        end * (coalesce(os.ownership_pct, eo.base_ownership_pct) / 100.0) as group_amount,
        {# PRD-4: NCI amount = translated x (1 - ownership_pct) #}
        etb.local_amount * case
            when etb.is_equity = 1 and hr.historical_rate is not null then hr.historical_rate
            when etb.is_balance_sheet = 1 then rl.closing_rate
            when etb.is_pnl = 1 then rl.average_rate
            else rl.closing_rate
        end * (1.0 - coalesce(os.ownership_pct, eo.base_ownership_pct) / 100.0) as nci_amount
    from entity_tb as etb
    inner join entity_ownership as eo
        on etb.data_area_id = eo.data_area_id
    {# PRD-9: Temporal ownership — period_date falls within [effective_date, end_date] #}
    left join ownership_staging as os
        on eo.consolidation_group = os.consolidation_group
        and etb.data_area_id = os.data_area_id
        and etb.period_date >= os.effective_date
        and etb.period_date <= os.end_date
    left join rate_lookup as rl
        on etb.accounting_currency = rl.from_currency
        and eo.reporting_currency = rl.to_currency
        and etb.period_date = rl.period_date
    {# PRD-10: Historical equity rate — latest rate_date <= period_date #}
    left join (
        select
            consolidation_group,
            data_area_id,
            main_account,
            rate_date,
            historical_rate,
            row_number() over (
                partition by consolidation_group, data_area_id, main_account
                order by rate_date desc
            ) as rn
        from {{ source('epm_staging', 'historical_equity_rates') }}
    ) as hr
        on eo.consolidation_group = hr.consolidation_group
        and etb.data_area_id = hr.data_area_id
        and etb.main_account = hr.main_account
        and hr.rn = 1
    {# PRD-14: Exclude equity-method entities — handled in separate model #}
    where coalesce(os.consolidation_method, eo.seed_method) != 'equity'
)

select * from consolidated
