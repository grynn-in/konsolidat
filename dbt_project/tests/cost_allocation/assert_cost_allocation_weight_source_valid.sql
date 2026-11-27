-- Weight rows have the shape their source declares (konsol#269 phase 2b-1, W2b).
-- Stub (red): returns no row, so the must_flag fixture fails the gate.
select w.parent as run, w.idx, w.source
from {{ source('epm_staging', 'cost_allocation_run_weights') }} as w
where 1 = 0
