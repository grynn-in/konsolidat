-- konsolidat#204 option (a), konsol#117 pair 2: nci_amount is the attribution amount, the
-- minority's share of each translated line: translated_amount x (1 - ownership_pct). It is no
-- longer the complement of group_amount (group_amount is 100% of translated_amount for a
-- controlled subsidiary); task K2 posts the sum of it as the single NCI line in equity.
select
    consolidation_group,
    data_area_id,
    fiscal_year,
    fiscal_period,
    main_account,
    ownership_pct,
    translated_amount,
    nci_amount,
    abs(nci_amount - translated_amount * (1 - ownership_pct)) as nci_diff
from {{ ref('gold_consolidated_trial_balance') }}
where abs(nci_amount - translated_amount * (1 - ownership_pct)) > 0.01
