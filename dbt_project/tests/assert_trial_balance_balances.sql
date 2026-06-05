-- Test: Sum of all debits must equal sum of all credits per entity/period
-- Fundamental double-entry accounting check
select
    data_area_id,
    fiscal_year,
    fiscal_period,
    abs(sum(period_debit) - sum(period_credit)) as imbalance
from {{ ref('gold_trial_balance') }}
group by data_area_id, fiscal_year, fiscal_period
having abs(sum(period_debit) - sum(period_credit)) > 0.01
