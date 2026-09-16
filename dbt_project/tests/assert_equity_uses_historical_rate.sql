-- PRD-10 Test: an account the chart DECLARES at the historical rate must be
-- translated at that rate (not the closing rate).
-- konsolidat#213: the declaration is uses_historical_rate (fx_method =
-- 'historical'), not is_equity — is_equity says what the account IS
-- (account_type = 'Equity'), which is konsol's deal-layer meaning and decides
-- nothing about translation. This test always meant the declaration.
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
where uses_historical_rate = 1
  and historical_equity_rate is not null
  and abs(translation_rate - historical_equity_rate) > 0.000001
