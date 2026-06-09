-- PRD-7 Test: variance_abs must equal actual_amount - budget_amount
select
    data_area_id,
    fiscal_year,
    fiscal_period,
    main_account,
    actual_amount,
    budget_amount,
    variance_abs,
    abs(variance_abs - (actual_amount - budget_amount)) as formula_diff
from {{ ref('gold_variance_analysis') }}
where budget_amount is not null
  and abs(variance_abs - (actual_amount - budget_amount)) > 0.01
