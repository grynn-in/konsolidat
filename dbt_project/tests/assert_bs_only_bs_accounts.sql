-- Test: Balance sheet view should only contain BS accounts (is_balance_sheet = 1)
-- The gold_balance_sheet model filters WHERE is_balance_sheet = 1, so no non-BS rows should appear
select
    data_area_id,
    main_account,
    fiscal_year,
    fiscal_period
from {{ ref('gold_trial_balance') }}
where is_balance_sheet = 1
  and main_account not in (select distinct main_account from {{ ref('gold_balance_sheet') }})
