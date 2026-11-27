-- Derived (Account Set) weights that no longer match the trial balance (konsol#269 phase 2b-1, W3).
-- Stub (red): returns no row, so the must_flag fixture fails the gate.
{{ config(severity='warn') }}
select w.parent as run, w.idx, w.driver_value
from {{ source('epm_staging', 'cost_allocation_run_weights') }} as w
where 1 = 0
