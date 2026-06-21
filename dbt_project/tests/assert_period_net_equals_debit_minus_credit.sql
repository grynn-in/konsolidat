-- Test: period_net_amount must equal period_debit - period_credit per trial balance row.
-- Fails on pre-fix gold until a full refresh rebuilds gold_trial_balance with the new measure.
select
    data_area_id,
    fiscal_year,
    fiscal_period,
    main_account,
    period_debit,
    period_credit,
    period_net_amount,
    abs(period_net_amount - (period_debit - period_credit)) as formula_diff
from {{ ref('gold_trial_balance') }}
where abs(period_net_amount - (period_debit - period_credit)) > 0.01