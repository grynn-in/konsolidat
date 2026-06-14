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

### Errors
Per-cell `errors[i]` → that cell returns a `#VALUE!`-style Custom Function error; other cells
in the batch still resolve. Auth failure (401/403) → instructive error directing the user to
open the task pane and log in.

## Deliverables

| File | Purpose |
|---|---|
| `excel-addin/src/functions.json` | Custom Functions metadata (names, params, types) |
| `excel-addin/src/functions.js` | Implementation + `CustomFunctions.associate`, debounced batcher |
| `excel-addin/src/functions.html` | Runtime page that loads `functions.js` |
| `excel-addin/manifest.xml` | + `CustomFunctions` extension point, namespace `K`, runtime resources |
| `excel-addin/package.json` | `deploy` script copies the 3 new files into `public/excel-addin/` |

`OpenEPM.bas` — **unchanged.**

## Open items / verification
- ⚠️ `taskpane.js` currently sends `measure:"amount", scenario:"actual"` in its batch refresh —
  drift from the backend defaults (`period_net_amount`/`actuals`). The Custom Functions use the
  correct defaults; the task pane should be reconciled separately.
- Not runtime-verified: needs a live konsol site + Office.js host (desktop Excel or web) to
  sideload `manifest.xml` and smoke-test recalc + write-back.
