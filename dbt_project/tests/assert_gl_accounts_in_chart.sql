-- Test: Every GL account in trial balance should exist in chart of accounts
select distinct
    tb.main_account
from {{ ref('gold_trial_balance') }} as tb
left join {{ ref('silver_main_accounts') }} as ma
    on tb.main_account = ma.main_account_id
where ma.main_account_id is null
