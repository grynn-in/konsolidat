-- konsolidat#204 option (a), konsol#117 pair 2 (IFRS 10.B86): layer 1 carries a controlled
-- subsidiary line by line at 100%. group_amount therefore equals translated_amount on every row
-- the model emits; the minority is not a share of each line but the one NCI line in equity that
-- konsol#117 pair 2 task K2 posts from nci_amount.
-- 'proportional' rides along until pair 3 gives it its own rule: the model emits it today and
-- this test does not exempt it.
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
where consolidation_method not in ('equity', 'none')
  and abs(group_amount - translated_amount) > 0.01
