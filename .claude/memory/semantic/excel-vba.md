# Excel VBA — OpenEPM.bas (updated 2026-06-08)

## Architecture
- `=EPM()` volatile functions return cached values (0 if not cached)
- Ctrl+Shift+R triggers batch refresh: scan sheet → collect EPM cells → POST /api/method/konsol.api.epm_batch → populate cache → recalculate via Union range
- Auth: cookie-based via MSXML2.ServerXMLHTTP.6.0, session cookie stored in module-level var
- Auto-login on first refresh, auto-retry on 401/403

## Key Files
- `excel/OpenEPM.bas` — all VBA code (single module)
- `excel/Open_EPM_Template.xlsx` — template workbook with EPM formulas

## API Endpoints (Frappe/konsol on port 8069)
- POST /api/method/login — auth (returns Set-Cookie)
- POST /api/method/konsol.api.epm_batch — batch value retrieval
- GET /api/method/konsol.api.health — connectivity check

## Macros
- EPM_Login — manual login
- EPM_Refresh — refresh active sheet (Ctrl+Shift+R)
- EPM_RefreshAll — refresh all sheets with progress
- EPM_ClearCache — clear cached values
- EPM_SetServer — change API URL
- EPM_ToggleLog — toggle _EPM_Log sheet (off by default)
- EPM_Debug — connectivity and formula diagnostics

## Resolved Issues (2026-06-08)
- Union range recalc replaces cell-by-cell loop (was hanging on 200+ cells)
- FetchError handler restores Application state (Calculation/EnableEvents/ScreenUpdating)
- Dead code removed (AuthenticatedRequest, pRefreshing)
- HTTP timeouts on retry path
- JsonEscape handles CR/LF/Tab
- DoEvents forces status bar repaint

## Remaining
- InputBox doesn't mask password (need UserForm or Office.js task pane — blocked by admin policy)
- Cube.js not needed — ClickHouse gold tables are already fast, bottleneck was Excel recalc not DB

## Performance Notes
- ClickHouse batch query: ~0.14s for 216 values
- Application.CalculateFull hangs (recalcs ALL volatile functions everywhere) — never use
- ws.Calculate also slow — triggers all volatile functions on sheet
- Union range .Calculate in manual mode is the correct approach
