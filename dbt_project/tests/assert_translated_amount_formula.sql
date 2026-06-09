-- PRD-1 Test: translated_amount must equal local_amount × translation_rate
select
    consolidation_group,
    data_area_id,
    fiscal_year,
    fiscal_period,
    main_account,
    local_amount,
    translation_rate,
    translated_amount,
    abs(translated_amount - (local_amount * translation_rate)) as formula_diff
from {{ ref('gold_consolidated_trial_balance') }}
where abs(translated_amount - (local_amount * translation_rate)) > 0.01
