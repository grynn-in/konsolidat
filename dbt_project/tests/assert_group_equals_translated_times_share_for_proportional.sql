-- IFRS 11.20, konsol#117 pair 3: a joint operation (consolidation_method 'proportional') is
-- carried line by line at the operator's share, so group_amount = translated_amount x
-- ownership_pct. A controlled subsidiary (full) is at 100% and has its own test,
-- assert_group_equals_translated_for_full.
select
    consolidation_group,
    data_area_id,
    fiscal_year,
    fiscal_period,
    main_account,
    ownership_pct,
    translated_amount,
    group_amount,
    abs(group_amount - translated_amount * ownership_pct) as share_diff
from {{ ref('gold_consolidated_trial_balance') }}
where consolidation_method = 'proportional'
  and abs(group_amount - translated_amount * ownership_pct) > 0.01
