{{
    config(
        engine='MergeTree()',
        order_by='(consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account)'
    )
}}

with entity_tb as (
    select
        tb.data_area_id,
        tb.fiscal_year,
        tb.fiscal_period,
        tb.main_account,
        tb.account_name,
        tb.account_type_name,
        tb.is_balance_sheet,
        tb.is_pnl,
        tb.dim_cost_center,
        tb.dim_department,
        tb.period_net_amount as local_amount,
        le.accounting_currency
    from {{ ref('gold_trial_balance') }} as tb
    inner join {{ ref('silver_legal_entities') }} as le
        on tb.data_area_id = le.data_area
),

consolidated as (
    select
        cg.consolidation_group,
        etb.data_area_id,
        etb.fiscal_year,
        etb.fiscal_period,
        etb.main_account,
        etb.account_name,
        etb.account_type_name,
        etb.is_balance_sheet,
        etb.is_pnl,
        etb.dim_cost_center,
        etb.dim_department,
        etb.local_amount,
        etb.accounting_currency,
        cg.reporting_currency,
        cg.ownership_pct / 100.0 as ownership_pct,
        cg.consolidation_method,
        -- Currency translation: use closing rate for BS, average for PnL
        -- Simplified: uses latest available rate for the period
        etb.local_amount * coalesce(
            (
                select er.exchange_rate
                from {{ ref('silver_exchange_rates') }} as er
                where er.from_currency = etb.accounting_currency
                  and er.to_currency = cg.reporting_currency
                  and er.valid_from <= toDate(
                      concat(toString(etb.fiscal_year), '-', lpad(toString(etb.fiscal_period), 2, '0'), '-01')
                  )
                order by er.valid_from desc
                limit 1
            ),
            1.0
        ) as translated_amount,
        -- Apply ownership percentage
        etb.local_amount * coalesce(
            (
                select er.exchange_rate
                from {{ ref('silver_exchange_rates') }} as er
                where er.from_currency = etb.accounting_currency
                  and er.to_currency = cg.reporting_currency
                  and er.valid_from <= toDate(
                      concat(toString(etb.fiscal_year), '-', lpad(toString(etb.fiscal_period), 2, '0'), '-01')
                  )
                order by er.valid_from desc
                limit 1
            ),
            1.0
        ) * (cg.ownership_pct / 100.0) as group_amount
    from entity_tb as etb
    inner join {{ ref('consolidation_groups') }} as cg
        on etb.data_area_id = cg.data_area_id
)

select * from consolidated
