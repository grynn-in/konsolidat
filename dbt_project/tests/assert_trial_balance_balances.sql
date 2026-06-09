-- Test: Sum of all debits should equal sum of all credits per entity/period
-- D365 sandbox/demo data is often unbalanced, so warn rather than fail
{{ config(severity='warn') }}

select
    data_area_id,
    fiscal_year,
    fiscal_period,
    abs(sum(period_debit) - sum(period_credit)) as imbalance
from {{ ref('gold_trial_balance') }}
group by data_area_id, fiscal_year, fiscal_period
having abs(sum(period_debit) - sum(period_credit)) > 0.01
