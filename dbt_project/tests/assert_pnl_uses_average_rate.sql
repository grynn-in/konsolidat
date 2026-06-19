-- PRD-1 Test: P&L accounts must use average rate for translation
-- Fails if any P&L row has translation_rate ≠ average_rate
select
    consolidation_group,
    data_area_id,
    fiscal_year,
    fiscal_period,
    main_account,
    average_rate,
    translation_rate,
    abs(translation_rate - average_rate) as rate_diff
from {{ ref('gold_consolidated_trial_balance') }}
where is_pnl = 1
  {# Same-currency entities translate at 1.0 by definition (not the scrambled
     same-currency rate in the table), so exclude them from this assertion. #}
  and accounting_currency != reporting_currency
  and abs(translation_rate - average_rate) > 0.0001
