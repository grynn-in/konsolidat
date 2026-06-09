-- PRD-1 Test: group_amount must equal translated_amount × ownership_pct
select
    consolidation_group,
    data_area_id,
    fiscal_year,
    fiscal_period,
    main_account,
    translated_amount,
    ownership_pct,
    group_amount,
    abs(group_amount - (translated_amount * ownership_pct)) as formula_diff
from {{ ref('gold_consolidated_trial_balance') }}
where abs(group_amount - (translated_amount * ownership_pct)) > 0.01
