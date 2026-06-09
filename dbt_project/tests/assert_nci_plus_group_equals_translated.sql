-- PRD-4 Test: group_amount + nci_amount must equal translated_amount
select
    consolidation_group,
    data_area_id,
    fiscal_year,
    fiscal_period,
    main_account,
    translated_amount,
    group_amount,
    nci_amount,
    abs(translated_amount - (group_amount + nci_amount)) as split_diff
from {{ ref('gold_consolidated_trial_balance') }}
where abs(translated_amount - (group_amount + nci_amount)) > 0.01
