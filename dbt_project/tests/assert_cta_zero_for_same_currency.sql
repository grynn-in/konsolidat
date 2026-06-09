-- PRD-2 Test: CTA must be zero when entity currency = reporting currency
select
    consolidation_group,
    data_area_id,
    fiscal_year,
    fiscal_period,
    cta_amount
from {{ ref('gold_fx_revaluation') }}
where accounting_currency = reporting_currency
  and abs(cta_amount) > 0.01
