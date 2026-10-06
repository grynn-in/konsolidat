-- PRD-1 Test: translated_amount must equal local_amount × translation_rate + retranslation_amount.
-- konsolidat#257: a balance sheet key declared at closing also carries its retranslation,
-- cum_local(prev) × (closing(p) − closing(prev)), on its own row; every other row carries 0.
select
    consolidation_group,
    data_area_id,
    fiscal_year,
    fiscal_period,
    main_account,
    local_amount,
    translation_rate,
    retranslation_amount,
    translated_amount,
    abs(translated_amount - (local_amount * translation_rate + retranslation_amount)) as formula_diff
from {{ ref('gold_consolidated_trial_balance') }}
where abs(translated_amount - (local_amount * translation_rate + retranslation_amount)) > 0.01
