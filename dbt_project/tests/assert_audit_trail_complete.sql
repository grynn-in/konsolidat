-- PRD-21 Test: Every allocation run must appear in the audit trail
select
    ar.allocation_run_id
from {{ source('epm_staging', 'allocation_runs') }} as ar
left join {{ ref('gold_allocation_audit_trail') }} as aat
    on ar.allocation_run_id = aat.allocation_run_id
where aat.allocation_run_id is null
