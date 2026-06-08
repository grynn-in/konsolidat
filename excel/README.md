# Excel VBA — OpenEPM

SmartView-style `=EPM()` formulas for retrieving financial data from ClickHouse
via the Frappe/konsol API.

## Setup

1. Open `Open_EPM_Template.xlsx`
2. Press **Alt+F11** to open the VBA Editor
3. **File > Import File** > select `OpenEPM.bas`
4. Save as `.xlsm` (macro-enabled)

On open, the module binds **Ctrl+Shift+R** to refresh.

## Functions

| Function | Description |
|----------|-------------|
| `=EPM(entity, year, period, account)` | Period net amount (actuals) |
| `=EPM(entity, year, period, account, measure, scenario, cost_center, dept)` | Full form |
| `=EPM_BUDGET(entity, year, period, account)` | Budget amount |
| `=EPM_VARIANCE(entity, year, period, account)` | Variance (absolute) |
| `=EPM_DEBIT(entity, year, period, account)` | Period debit |
| `=EPM_CREDIT(entity, year, period, account)` | Period credit |

Arguments can be cell references (e.g., `=EPM($B$2, $C$1, D$1, $A5)`).

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| **Ctrl+Shift+R** | Refresh active sheet (fetch + recalculate) |
| **F9** | Recalculate all sheets (no fetch, uses cache) |
| **Ctrl+Alt+F9** | Force recalculate all sheets |

## Macros (Alt+F8)

| Macro | Description |
|-------|-------------|
| `EPM_Login` | Log in to Frappe (prompted automatically on first refresh) |
| `EPM_Refresh` | Refresh active sheet |
| `EPM_RefreshAll` | Refresh all sheets with progress |
| `EPM_ClearCache` | Clear cached values |
| `EPM_SetServer` | Change API server URL (default: `http://localhost:8069`) |
| `EPM_ToggleLog` | Toggle logging to `_EPM_Log` sheet (off by default) |
| `EPM_Debug` | Connectivity and formula diagnostics |

## How It Works

1. `=EPM()` formulas return cached values (or 0 if not yet fetched)
2. **Ctrl+Shift+R** scans the sheet, collects all EPM cells, sends ONE batch
   POST to `/api/method/konsol.api.epm_batch`
3. API returns all values in a single response
4. VBA populates the cache and recalculates only the EPM cells (Union range)

Formulas are **not volatile** — they only recalculate when their input
arguments change or on explicit refresh. This prevents recalc storms in
large workbooks.

## Logging

Run `EPM_ToggleLog` to enable. A `_EPM_Log` sheet is created with columns:

| Timestamp | Level | Message |
|-----------|-------|---------|
| 2026-06-08 10:30:00 | INFO | Logged in as Administrator |
| 2026-06-08 10:30:01 | INFO | Trial Balance: found 216 EPM formulas |
| 2026-06-08 10:30:02 | INFO | Trial Balance: refreshed 216 cells |
