-- PRD-21 Test: gold_allocation_results must only contain active run results
-- Reversed runs should only appear in audit trail
select
    aat.allocation_run_id,
    aat.run_status
from {{ ref('gold_allocation_audit_trail') }} as aat
where aat.run_status = 'Reversed'
  and aat.allocated_amount > 0
  and exists (
    select 1 from {{ ref('gold_allocation_results') }} as ar
    where ar.fiscal_year = aat.fiscal_year
      and ar.fiscal_period = aat.fiscal_period
      and ar.allocation_rule_id = aat.allocation_rule_id
      and ar.allocated_amount = aat.allocated_amount
  )
limit 10
