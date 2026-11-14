-- IFRS 11.20, konsol#117 pair 3: the operator carries only its own share of a joint
-- operation's assets and liabilities, so no one holds a minority in it and nci_amount is 0.
-- (A controlled subsidiary's nci_amount is the attribution amount; see
-- assert_nci_equals_translated_times_minority.)
select
    consolidation_group,
    data_area_id,
    fiscal_year,
    fiscal_period,
    main_account,
    consolidation_method,
    nci_amount
from {{ ref('gold_consolidated_trial_balance') }}
where consolidation_method = 'proportional'
  and abs(nci_amount) > 0.01
