-- PRD-4 Test: NCI amount must be zero for fully-owned entities
select
    consolidation_group,
    data_area_id,
    fiscal_year,
    fiscal_period,
    main_account,
    ownership_pct,
    nci_amount
from {{ ref('gold_consolidated_trial_balance') }}
where abs(ownership_pct - 1.0) < 0.0001
  and abs(nci_amount) > 0.01
