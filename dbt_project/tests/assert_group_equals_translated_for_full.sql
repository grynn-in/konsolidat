-- konsolidat#204 option (a), konsol#117 pair 2 (IFRS 10.B86): layer 1 carries a controlled
-- subsidiary line by line at 100%. group_amount therefore equals translated_amount on every row
-- the model emits; the minority is not a share of each line but the one NCI line in equity that
-- konsol#117 pair 2 task K2 posts from nci_amount.
-- A joint operation (proportional, IFRS 11.20) is carried at the operator's share and has its own
-- test, assert_group_equals_translated_times_share_for_proportional.
select
    consolidation_group,
    data_area_id,
    fiscal_year,
    fiscal_period,
    main_account,
    consolidation_method,
    translated_amount,
    group_amount,
    abs(group_amount - translated_amount) as share_diff
from {{ ref('gold_consolidated_trial_balance') }}
where consolidation_method = 'full'
  and abs(group_amount - translated_amount) > 0.01
