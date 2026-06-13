# PRD: Rolling Forecasts

**Status:** Not Started
**Date:** 2026-06-13
**Phase:** Phase 6.3 — Analytical Gaps
**Repos:** `konsolidat` (dbt/data stack), `konsol` (Frappe app)

## Problem

- All planning scenarios today are fixed-year. `scenario_definitions.csv` carries `scenario_type` of `actual`/`budget`/`forecast`/`whatif`, and `gold_scenario_trial_balance` unions whole fiscal years per scenario. There is no concept of a window that advances over time.
- A `forecast` scenario is just a budget with a different `scenario_id` (see budget-layers.md "Forecast Uses the Same Structure"). It still spreads an annual amount across 12 calendar periods of one `fiscal_year` — it cannot blend actuals for elapsed months with forecast for remaining months.
- Finance teams need a continuously-refreshed **12-month forward view** (actual for closed periods, forecast for open periods) that re-anchors every month-end close. Producing this manually means re-keying the window each month and hand-stitching `actual` and `forecast` rows in Excel.
- There is no stored notion of which periods are *closed*. `gold_scenario_trial_balance` exposes a `data_source` column (`gl` / `d365_budget` / `api_input`) but nothing marks the actual/forecast boundary, so a rolling blend cannot be expressed downstream.

## Solution

Introduce a `rolling` scenario type whose effective output is a 12-period forward window anchored at the latest closed period: GL actuals for closed periods spliced with `forecast`-layer amounts for open periods. A new `gold_rolling_forecast` dbt model computes the splice from a period-close anchor, and `=EPM(..., "rolling")` resolves the same window for Excel.

## Scope

### 1. Scenario type `rolling`

Add `rolling` to the allowed scenario types so it ties into existing scenario management.

| Artifact | Change |
|---|---|
| `seeds/scenario_definitions.csv` | New row, e.g. `ROLLING_FC,Rolling Forecast,rolling,1` |
| Frappe `Scenario Definition` doctype (`scenario_type` Select) | Append `rolling` to existing options (`actual\nbudget\nforecast\nstrategic\noperational`) |
| `Scenario Definition` doctype | New fields: `source_forecast_scenario` (Link → Scenario Definition; the forecast supplying open-period amounts), `window_length` (Int, default 12) |

### 2. Period-close anchor

The actual/forecast boundary is data-driven, not hardcoded. A rolling forecast anchors on the latest closed period.

| Artifact | Definition |
|---|---|
| `seeds/period_close_status.csv` | Grain: `data_area_id, fiscal_year, fiscal_period, period_status` where `period_status ∈ {open, closed}`. Joined per entity (entities already keyed in `entity_fiscal_calendars.csv`). |
| dbt macro `latest_closed_period()` | Returns `(fiscal_year, fiscal_period)` of the max closed period per `data_area_id`. Single source of truth for the splice boundary. |

### 3. `gold_rolling_forecast` dbt model

`models/gold/gold_rolling_forecast.sql` — produces a 12-period forward window per `data_area_id`, starting at `latest_closed_period() + 1` and wrapping across the fiscal-year boundary.

| Column | Source |
|---|---|
| `scenario_id` | The `rolling` scenario id (e.g. `ROLLING_FC`) |
| `data_area_id`, `fiscal_year`, `fiscal_period`, `main_account` | window grain |
| `{{ dim_select(dims=get_budget_dimensions()) }}` | budget dimensions (matches `gold_spread_budget` / `gold_scenario_trial_balance`) |
| `amount` | actuals from `gold_trial_balance.period_net_amount` for closed periods; forecast `period_amount` from `gold_spread_budget` (filtered to `source_forecast_scenario`) for open periods |
| `window_offset` | 1–12, distance from anchor (for "month +N" reporting) |
| `data_source` | `gl` for closed periods, `api_input` for forecast periods (reuse existing labels) |

Splice rule: for each `(entity, year, period)` in the forward window, take `gl` actual if `period_status = closed`, else the forecast amount. The window length is `window_length` (default 12) from the Scenario Definition.

### 4. Cross-scenario integration

| Artifact | Change |
|---|---|
| `gold_scenario_trial_balance.sql` | Add a `union all` branch selecting from `gold_rolling_forecast` so rolling appears alongside actual/budget/forecast for variance and cross-scenario analysis |
| Cube.js semantic layer | `gold_rolling_forecast` exposed as a measure source; `window_offset` available as a dimension |

### 5. Excel / API retrieval

| Surface | Behaviour |
|---|---|
| `=EPM("USMF", 2025, 5, "6100", "period_amount", "rolling")` | Resolves the rolling window; returns actual if period 5 is closed, forecast otherwise |
| Frappe `api.py` query builder | Routes `scenario_type = rolling` to `gold_rolling_forecast`; period-range syntax (`"Q1"`, `"FY"`) works as in budgeting-guide.md |
| Forecast layers | Open-period forecast amounts come from the existing additive layer structure (`base + challenge + management + board`) of `source_forecast_scenario` via `gold_spread_budget` — no new layer mechanics |

## Out of Scope

- Driver-based or volume×price forecasting for the open periods (Phase 6.8 Planning Enhancements).
- Auto-detecting period close from GL postings — close status is set explicitly via `period_close_status.csv` / Frappe, not inferred.
- Multi-GAAP rolling windows (Phase 6.2) and consolidated/FX-translated rolling forecasts beyond what `gold_trial_balance` already provides.
- Automatic monthly re-seeding/scheduling of the window — the window recomputes on each `dbt build`; cron orchestration is out of scope here.
- A bespoke rolling-forecast input UI; forecast amounts reuse the existing Budget Input doctype + workflow.

## Acceptance Criteria

1. `dbt seed` loads `scenario_definitions.csv` containing a row with `scenario_type = rolling`; `Scenario Definition` doctype accepts and saves `rolling`.
2. `gold_rolling_forecast` returns exactly `window_length` periods (default 12) per `data_area_id`, with `window_offset` ranging 1–12 and no gaps.
3. For any entity, every window period with `period_status = closed` has `data_source = gl` and `amount` equal to the matching `gold_trial_balance.period_net_amount`; every `open` period has `data_source = api_input` and `amount` from the `source_forecast_scenario`'s `gold_spread_budget`.
4. dbt test `assert_rolling_window_anchored`: the minimum window period for each entity = `latest_closed_period() + 1` (wrapping year-end correctly).
5. dbt test `assert_rolling_no_period_overlap`: no `(entity, year, period)` appears with both `gl` and `api_input` in `gold_rolling_forecast`.
6. `gold_scenario_trial_balance` includes the `rolling` scenario; a cross-scenario query returns `actual`, `budget`, `forecast`, and `rolling` for the same `(entity, account, period)`.
7. `=EPM("USMF", <yr>, <closed period>, "6100", "period_amount", "rolling")` returns the GL actual; the same call for an open period returns the forecast amount; `"FY"` sums all 12 window periods.
8. Advancing one period in `period_close_status.csv` and rebuilding shifts the window forward by exactly one period (drops the new actual's prior forecast, appends a new forward forecast month).

## Open Questions

- Anchor granularity: one global `latest_closed_period()` vs per-entity anchors when entities close on different calendars (`entity_fiscal_calendars.csv` already allows divergent calendars). Default assumption above is **per-entity**.
- Should `window_length` be fixed at 12 or support 18/24-month rolling views? Modelled as configurable; default 12.
- Where the rolling window crosses a fiscal-year boundary, does forecast for the next year come from a separate `forecast` scenario for that year, or is the window capped at the current `source_forecast_scenario`'s horizon?
- Should closing a period in Frappe auto-trigger a `dbt build` (re-anchor), or is re-anchor tied to the existing scheduled pipeline run?
