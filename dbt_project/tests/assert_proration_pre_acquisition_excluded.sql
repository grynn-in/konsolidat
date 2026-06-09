-- PRD-11 Test: Pre-acquisition P&L amounts must be excluded (adjustment_amount < 0)
select
    consolidation_group,
    data_area_id,
    fiscal_year,
    fiscal_period,
    main_account,
    adjustment_amount
from {{ ref('gold_acquisition_adjustments') }}
where adjustment_type = 'pnl_proration'
  and adjustment_amount > 0.01
