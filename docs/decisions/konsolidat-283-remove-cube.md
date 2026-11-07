# Decision: Remove Cube from the stack (konsolidat #283)

**Issue:** grynn-in/konsolidat#283 · **Decided by:** Deepak Pai, 7 Nov 2026 (konsol#232 ratified "do not wire Cube"; option (b), removal, accepted)

## Context
Cube.js (`cubejs/cube:v0.36`) shipped in the compose stack since the first
deploy script (PRs #7 and #9) as a planned semantic layer for Excel ODBC and
BI reads. By 7 Nov 2026, measured on `54d072a`: no konsol code referenced it
or port 4000; the Caddyfile proxied `/api/method/konsol.cube_proxy/*` to a
konsol endpoint that never existed; eight hand-written schema files under
`cube/` had not changed since June and duplicated konsol's Dataset / Measure
registry; two konsolidat tests asserted Cube was a "core component"; the
running container used 100 MiB RSS at 0% CPU, and every deploy generated a
`CUBEJS_API_SECRET` nobody used.

## Options
### (a) Record only; Cube stays deployed and idle
- **+** No change to deploy.
- **−** Every customer deploy ships a container nobody calls, a secret, and a
  dead proxy route; the tests keep asserting a falsehood.

### (b) Remove Cube from the stack — **chosen**
- **+** The stack is what it says it is; one read path; fewer secrets.
- **−** Re-adding a semantic layer later is a new piece of work (but ClickHouse
  views over gold come first; see reopen conditions).

### (c) Leave open
- **−** Keeps an unowned conclusion in the register.

## Decision
(b). Removed: the `cubejs` service and Caddy's `depends_on` on it, the two
Caddy routes, the deploy.sh secret generation / start / URL lines, the
`CUBEJS_*` env entries, the `cube/` directory, `scripts/generate_cube_schemas.py`,
the `cube-schema` Makefile target, and the two tests' Cube assertions (now
asserting absence). Kept: konsol's `cube_type` field on Dimension and Measure
(a type / aggregation field read by six modules; the dbt vars konsol writes
carry it), and the PRDs and design notes that mention Cube, as history.

## Consequences
- Existing stacks: `docker compose up -d --remove-orphans` removes the stopped
  `konsolidat_cubejs` container at the next deploy; Cube had no named volume.
  `CUBEJS_*` lines in an existing `.env` are inert and may be deleted.
- Reopen conditions stay on konsol#232: a measured query near a second after
  konsol#231; a BI client needing a semantic layer; concurrency rather than
  latency as the limit. ClickHouse views over gold are the first answer.
