-- PRD-2 Test: CTA must be non-zero when closing rate != average rate for an entity
-- Join fx_revaluation with consolidated TB to check rate divergence
with rate_check as (
    select
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        max(closing_rate) as max_closing_rate,
        max(average_rate) as max_average_rate
    from {{ ref('gold_consolidated_trial_balance') }}
    where accounting_currency != reporting_currency
    group by consolidation_group, data_area_id, fiscal_year, fiscal_period
    having abs(max(closing_rate) - max(average_rate)) > 0.0001
)

select
    rc.consolidation_group,
    rc.data_area_id,
    rc.fiscal_year,
    rc.fiscal_period,
    rc.max_closing_rate,
    rc.max_average_rate,
    coalesce(fx.cta_amount, 0) as cta_amount
from rate_check as rc
left join {{ ref('gold_fx_revaluation') }} as fx
    on rc.consolidation_group = fx.consolidation_group
    and rc.data_area_id = fx.data_area_id
    and rc.fiscal_year = fx.fiscal_year
    and rc.fiscal_period = fx.fiscal_period
where coalesce(fx.cta_amount, 0) = 0
