# Excel Integration

## SmartView-style EPM functions
- VBA module: excel/OpenEPM.bas
- Template: excel/Open_EPM_Template.xlsx
- Functions: =EPM(), =EPM_BUDGET(), =EPM_VARIANCE(), =EPM_DEBIT(), =EPM_CREDIT()

## How it works (batch mode like HsGetValue)
1. User writes =EPM(entity, year, period, account) in cells — returns cached value or 0
2. User presses Ctrl+Shift+R (EPM_Refresh macro)
3. VBA scans sheet, collects ALL EPM cells, sends ONE POST to /api/v1/epm/batch
4. API returns all values in one response
5. VBA populates cache, recalculates sheet

## API endpoints (Frappe/konsol on port 8069) — updated 2026-06-08
- POST /api/method/konsol.api.epm_batch — batch value retrieval (for VBA)
- GET /api/method/konsol.api.epm_value — single value retrieval
- GET /api/method/konsol.api.health — connectivity check
- POST /api/method/login — cookie-based auth (required before API calls)

## Cube.js (port 4000 / 15432)
- 4 cubes: trial_balance, consolidated_trial_balance, scenario_trial_balance, allocation_results
- SQL API on port 15432 (Postgres wire protocol) — needs Npgsql driver for Excel Power Query (user can't install)
- REST API on port 4000 — works but JSON parsing in Power Query is clunky
- User prefers the VBA =EPM() approach over Power Query

## Key user preferences
- Wants HsGetValue-like experience (formulas + refresh button)
- Does NOT want Power Query (unfamiliar with it)
- Cannot install Npgsql driver
- Data always flows through Airbyte → ClickHouse (no shortcuts)
