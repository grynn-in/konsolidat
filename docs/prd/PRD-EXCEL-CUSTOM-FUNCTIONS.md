# PRD: Excel Custom Functions (`=K.EPM()`)

**Status:** Proposed
**Date:** 2026-06-14
**Repos:** `konsol` (Office.js add-in served from `public/excel-addin/`), `konsolidat` (`excel-addin/` source + docs)

## Problem

The only live `=EPM()` worksheet-formula experience today is **VBA** (`excel/OpenEPM.bas`),
which requires:

- macro-enabled workbooks (`.xlsm`) and a user who will enable macros,
- Windows + desktop Excel (no Mac, no Excel on the web),
- a manual **Refresh** (Ctrl+Shift+R) — `=EPM()` returns `0`/cached until the batch runs.

The Office.js add-in (`excel-addin/`) already exists but only does **pipeline
orchestration** (login, trigger builds, status) plus a button-driven batch refresh. It does
**not** expose worksheet functions.

## Goal

Ship installable **Office.js Custom Functions** that provide a live, auto-recalculating
`=K.EPM(...)` family — cross-platform (Windows / Mac / web), no macros — **alongside** the
existing VBA. The VBA `=EPM()` stays fully intact (needed for demos).

### Non-goals

- Retiring `OpenEPM.bas` (explicitly kept).
- A dotless `=EPM()` from the add-in — impossible with Custom Functions (would require an
  XLL/Excel-DNA build). The VBA already provides the bare `=EPM()`.

## Naming — namespace `K`

Custom Functions are **always** namespaced: `=NAMESPACE.NAME(...)`. We use namespace **`K`**:

- shortest to type (`=K.EPM(...)`),
- visually distinct from the VBA's bare `=EPM(...)` — at a glance you can tell which engine
  ran a cell (useful in demos where both are present in one workbook),
- function names stay identical to the VBA (EPM, EPM_BUDGET, …) so there's nothing new to learn.

VBA `=EPM()` and add-in `=K.EPM()` **cannot collide** — different names, different runtimes;
a single workbook can use both.

## Function inventory (parity with `OpenEPM.bas`)

### Read (scalar)

| Function | Maps to `epm_batch` request |
|---|---|
| `=K.EPM(entity, year, period, account, [measure], [scenario], [cost_center], [department], [scenario_id])` | direct |
| `=K.EPM_BUDGET(entity, year, period, account, [cost_center], [department], [scenario_id])` | `measure="period_amount", scenario="budget"` |
| `=K.EPM_VARIANCE(...)` | `measure="variance_abs", scenario="variance"` |
| `=K.EPM_DEBIT(entity, year, period, account, [cost_center], [department])` | `measure="period_debit", scenario="actuals"` |
| `=K.EPM_CREDIT(...)` | `measure="period_credit", scenario="actuals"` |

Defaults match the backend (`konsol.api.epm_value`): `measure="period_net_amount"`,
`scenario="actuals"`. `period` accepts `1`–`12`, `Q1`–`Q4`, `H1`–`H2`, `FY`.

### Write

| Function | Maps to |
|---|---|
| `=K.EPMSAVE(amount, entity, year, period, account, scenario_id, layer, [cost_center], [department])` | POST `konsol.api.budget_cell_save`; returns `amount` |

`layer` ∈ {base, challenge, management, board}; `period` 1–12.

## Design

### Transport — reuse existing infra
- Served same-origin by Frappe at `/assets/konsol/excel-addin/`; all `fetch()` use **relative
  paths** + `credentials: "include"` → **no CORS**, cookie session auth. (Same as the task pane.)
- Read calls hit `POST /api/method/konsol.api.epm_batch` (bare JSON array). Response is Frappe-
  wrapped: `data.message.values[]` (+ optional `data.message.errors[]`).
- Write calls hit `POST /api/method/konsol.api.budget_cell_save`.

### Auto-batching (the key win over VBA)
No manual Refresh. Each `=K.EPM()` invocation enqueues its request and resolves a Promise; a
short debounce (one tick) coalesces every pending cell into **one** `epm_batch` POST, then
resolves each cell by index. A full grid recalc → a single round-trip. Respects
`MAX_BATCH_SIZE = 2000` by chunking.

### Auth — shared runtime (required)
The functions authenticate with the **same session cookie** the task pane sets at login. A
default custom-functions runtime is **JavaScript-only and does not support cookies**, so
`fetch(credentials:"include")` would always 401. The manifest therefore declares a **shared
runtime** (`<Runtimes lifetime="long">` + `SharedRuntime` requirement, `CustomFunctions` under
`<AllFormFactors>`): the task pane and the functions share one browser runtime and one cookie
jar. The shared page is `taskpane.html`/`index.html`, which loads `functions.js`. The user must
still **sign in via the pane first**; until then every `=K.EPM` cell returns an instructive
"not logged in" error.

### Errors
Per-cell `errors[i]` → that cell returns a `#VALUE!`-style Custom Function error; other cells in
the batch still resolve. Missing data (`values[i]` null) → `0` (matches the VBA). Auth/HTTP
failure on a read → all cells in that chunk error with a guiding message. A non-numeric `year`
is rejected **client-side** (it would otherwise 500 the whole batch server-side).

### Write-back (`EPMSAVE`) — VBA parity
Mirrors the VBA `EPMSAVE`: a per-cell **save cache** skips re-POSTing unchanged cells (custom
functions are volatile and recalc often), and on a failed write the function **returns the typed
amount** (best-effort, not cached so it retries) rather than replacing the value with `#VALUE!`.

## Deliverables

| File | Purpose |
|---|---|
| `excel-addin/src/functions.json` | Custom Functions metadata (names, params, types) |
| `excel-addin/src/functions.js` | Implementation + `CustomFunctions.associate`, debounced batcher, `postJson` helper, save cache |
| `excel-addin/manifest.xml` | `CustomFunctions` extension point (under `<AllFormFactors>`), namespace `K`, **shared runtime** |
| `excel-addin/src/taskpane.html` | Shared page also loads `functions.js` to register the functions |
| `excel-addin/package.json` | `deploy` script copies the new files into `public/excel-addin/` |

`OpenEPM.bas` — **unchanged.** (The standalone `functions.html` was removed; the shared page hosts the functions.)

## Open items / verification
- Not runtime-verified: needs a live konsol site + Office.js host (desktop Excel or web) to
  sideload `manifest.xml` and smoke-test recalc, the shared-runtime cookie auth, and write-back.
- Backend hardening follow-up (separate `konsol` PR): `epm_batch` does `int(req["year"])`
  **outside** its per-cell try/except, so a bad `year` 500s the whole batch. The client now
  guards this, but the server should also fail just the offending row.
- The microtask debounce coalesces cells enqueued in one synchronous turn; confirm on a real
  host that a large recalc still collapses to one POST (else switch to `setTimeout(flush, 0)`).
