-- PRD-1 Test: Balance sheet accounts must use closing rate for translation
-- Fails if any BS row has translation_rate ≠ closing_rate
select
    consolidation_group,
    data_area_id,
    fiscal_year,
    fiscal_period,
    main_account,
    closing_rate,
    translation_rate,
    abs(translation_rate - closing_rate) as rate_diff
from {{ ref('gold_consolidated_trial_balance') }}
where is_balance_sheet = 1
  and abs(translation_rate - closing_rate) > 0.0001
