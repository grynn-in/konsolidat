-- PRD-10 Test: Equity accounts with historical rates must use the historical rate
-- (not closing rate) for translation
select
    consolidation_group,
    data_area_id,
    main_account,
    fiscal_year,
    fiscal_period,
    translation_rate,
    historical_equity_rate,
    closing_rate
from {{ ref('gold_consolidated_trial_balance') }}
where is_equity = 1
  and historical_equity_rate is not null
  and abs(translation_rate - historical_equity_rate) > 0.000001
