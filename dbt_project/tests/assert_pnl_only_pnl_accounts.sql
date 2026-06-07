-- Test: P&L view should only contain P&L accounts (is_pnl = 1 on each row)
-- The gold_pnl_by_period model filters WHERE is_pnl = 1, so no non-PnL rows should appear
select
    data_area_id,
    main_account,
    fiscal_year,
    fiscal_period
from {{ ref('gold_trial_balance') }}
where is_pnl = 1
  and main_account not in (select distinct main_account from {{ ref('gold_pnl_by_period') }})
