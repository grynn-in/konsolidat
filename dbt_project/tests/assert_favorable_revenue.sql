-- PRD-7 Test: Revenue accounts where actual > budget should be marked favorable
select
    data_area_id,
    fiscal_year,
    fiscal_period,
    main_account,
    account_type_name,
    actual_amount,
    budget_amount,
    variance_favorable
from {{ ref('gold_variance_analysis') }}
where is_pnl = 1
  and account_type_name in ('Revenue', 'Income')
  and actual_amount > budget_amount
  and budget_amount is not null
  and variance_favorable = false
