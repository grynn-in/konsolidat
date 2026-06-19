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
        {# Signed double-entry movement (debit − credit). NOT period_net_amount,
           which is a positive magnitude (see #64) and would make the local TB
           fail to sum to zero, so no FX/CTA plug could ever balance it. #}
        tb.period_debit - tb.period_credit as local_amount,
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
        {# ClickHouse fills an unmatched LEFT JOIN with the column default (0),
           not NULL, so coalesce() would lock in 0 on a hierarchy miss. Fall back
           to the seed ownership when the hierarchy has no row. #}
        if(ho.hierarchy_ownership_pct != 0, ho.hierarchy_ownership_pct, cg.ownership_pct) as base_ownership_pct
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
        toFloat64(historical_rate) as historical_rate
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
        coalesce(toFloat64(cr.rate), toFloat64(dr.rate), 1.0) as closing_rate,
        coalesce(toFloat64(ar.rate), toFloat64(dr.rate), 1.0) as average_rate
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

{# Resolve per-row rate, ownership and translation_rate once.
   PRD-1 + PRD-10: translation rate depends on account type — equity → historical
   (fallback closing), BS → closing, PnL → average. A same-currency entity
   (accounting = reporting) ALWAYS translates at 1.0 regardless of what the rate
   table happens to contain (it carries scrambled same-currency rows, e.g.
   USD→USD ≠ 1 / CHF→CHF absent), so the local TB passes through unchanged and
   produces zero CTA. #}
rated as (
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
        {# PRD-9: Temporal ownership — use staging period match, else hierarchy/seed.
           The asof LEFT JOIN fills a miss with the default (0 / ''), not NULL, so
           coalesce() would wrongly lock 0% / '' for every entity without a
           temporal ownership row (e.g. all of GROUP_CORP — staging holds only
           AMG). Fall back to the base ownership / seed method on a miss. #}
        if(os.ownership_pct != 0, os.ownership_pct, eo.base_ownership_pct) / 100.0 as ownership_pct,
        if(os.consolidation_method != '', os.consolidation_method, eo.seed_method) as consolidation_method,
        rl.closing_rate as closing_rate,
        rl.average_rate as average_rate,
        {# PRD-10: Historical equity rate lookup #}
        hr.historical_rate as historical_equity_rate,
        case
            when etb.accounting_currency = eo.reporting_currency then 1.0
            when etb.is_equity = 1 and hr.historical_rate is not null then hr.historical_rate
            when etb.is_balance_sheet = 1 then rl.closing_rate
            when etb.is_pnl = 1 then rl.average_rate
            else rl.closing_rate
        end as translation_rate
    from entity_tb as etb
    inner join entity_ownership as eo
        on etb.data_area_id = eo.data_area_id
    {# PRD-9: Temporal ownership — period_date falls within [effective_date, end_date] #}
    asof left join ownership_staging as os
        on eo.consolidation_group = os.consolidation_group
        and etb.data_area_id = os.data_area_id
        and etb.period_date >= os.effective_date
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
            toFloat64(historical_rate) as historical_rate,
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
    {# PRD-14: Exclude equity-method entities — handled in separate model.
       Use the same default-aware resolution as the column above. #}
    where if(os.consolidation_method != '', os.consolidation_method, eo.seed_method) != 'equity'
),

consolidated as (
    select
        *,
        {# Translated amount = local x translation_rate #}
        local_amount * translation_rate as translated_amount,
        {# PRD-4: Group amount = translated x ownership_pct #}
        local_amount * translation_rate * ownership_pct as group_amount,
        {# PRD-4: NCI amount = translated x (1 - ownership_pct) #}
        local_amount * translation_rate * (1.0 - ownership_pct) as nci_amount
    from rated
)

select * from consolidated
