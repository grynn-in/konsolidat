# PRD: Reporting Enhancements (Waterfall, Trend, Commentary)

**Status:** Not Started
**Date:** 2026-06-13
**Phase:** Phase 6.9 — Analytical Gaps
**Repos:** `konsolidat` (dbt/data stack), `konsol` (Frappe app)

## Problem

- `gold_variance_analysis` reports `variance_abs` / `variance_pct` / `variance_favorable` at the account/period grain (see variance-analysis.md), but says *nothing about why* a variance occurred. Its own Out of Scope section explicitly defers waterfall (price/volume/mix), trend, and commentary. This PRD closes those three gaps.
- There is no **bridge/waterfall** decomposition. A revenue variance of 5,000 cannot be split into the part driven by price vs. volume vs. mix, so analysts rebuild bridges by hand in Excel.
- There is no **trend** model. The catalog has point-in-time aggregations (`gold_ytd_trial_balance`, `gold_pnl_quarterly`) and `gold_prior_year_comparison` (YoY only), but no sequential period-over-period (PoP) delta or rolling-average smoothing for spotting momentum.
- There is **no place to store narrative**. Variance numbers are recomputed on every `dbt build`, so commentary cannot live in dbt; it must be a Frappe doctype keyed to a variance cell, and surfaced back through `api.py` / Cube.js alongside the number.

## Solution

Add two gold models — `gold_variance_bridge` (price/volume/mix decomposition) and `gold_trend_analysis` (PoP delta + rolling averages) — both built on the existing `gold_scenario_trial_balance` / `gold_trial_balance` grain, and a Frappe `Variance Commentary` doctype that attaches narrative to a variance cell and is joined back at query time so a variance can be retrieved with its explanation.

## Scope

### 1. `gold_variance_bridge` — price/volume/mix decomposition

`models/gold/gold_variance_bridge.sql`. Decomposes the actual-vs-budget `variance_abs` of a P&L account into price, volume, and mix effects, using a statistical **quantity** fact alongside the financial amount. Quantity comes from the Fact Registry (PRD Fact Registry — statistical facts like `Revenue by Product`); when no quantity exists for an account the row falls back to a single `price` bucket (full variance) so the bridge always reconciles.

| Column | Definition |
|---|---|
| `data_area_id`, `fiscal_year`, `fiscal_period`, `main_account`, `account_name`, `account_type_name` | grain (matches `gold_variance_analysis`) |
| `{{ dim_select(dims=get_budget_dimensions()) }}` | budget dimensions (same set as `gold_variance_analysis`) |
| `actual_amount`, `budget_amount`, `variance_abs` | passthrough from `gold_variance_analysis` |
| `actual_qty`, `budget_qty` | summed quantity for the account from the statistical fact (null when absent) |
| `price_effect` | `(actual_price − budget_price) × actual_qty`, where `*_price = amount / nullif(qty,0)` |
| `volume_effect` | `(actual_qty − budget_qty) × budget_price` |
| `mix_effect` | residual = `variance_abs − price_effect − volume_effect` (guarantees full reconciliation) |
| `bridge_method` | `pvm` when quantity present, else `price_only` (price_effect = variance_abs, others 0) |

Standard decomposition identity: `price_effect + volume_effect + mix_effect = variance_abs` for every row.

### 2. `gold_trend_analysis` — PoP + rolling averages

`models/gold/gold_trend_analysis.sql`. Sequential trend over `gold_trial_balance` ordered by `(fiscal_year, fiscal_period)` per `(data_area_id, main_account, <budget dims>)`, using ClickHouse window functions.

| Column | Definition |
|---|---|
| grain + dims | as `gold_trial_balance` (`+ dim_select`) |
| `period_net_amount` | current period actual (passthrough) |
| `prior_period_amount` | `lagInFrame(period_net_amount, 1)` over the ordered partition |
| `pop_variance_abs` | `period_net_amount − prior_period_amount` |
| `pop_variance_pct` | `pop_variance_abs / nullif(prior_period_amount, 0) × 100` |
| `rolling_3m_avg` | trailing 3-period mean (`avg ... rows between 2 preceding and current row`) |
| `rolling_12m_avg` | trailing 12-period mean |
| `seq_index` | running period sequence number (for charting / x-axis) |

Period sequencing reuses `gold_period_hierarchy` for the year/period ordering so the lag wraps fiscal-year boundaries correctly.

### 3. `Variance Commentary` doctype (narrative on a cell)

New Frappe doctype `konsol/epm/doctype/variance_commentary/`. One record annotates one variance cell, identified by the same natural key the gold models expose.

| Field | Type | Notes |
|---|---|---|
| `data_area_id` | Link (Entity) | cell key |
| `fiscal_year` | Int | cell key |
| `fiscal_period` | Data | cell key (supports `1`–`12`, `Q1`, `FY` to match EPM period syntax) |
| `main_account` | Data | cell key |
| `scenario_compare` | Data | which comparison, e.g. `ACTUAL_vs_BUDGET` (default), `pop`, `yoy` |
| `dimension_context` | Small Text (JSON) | optional `{cost_center, department, ...}` so commentary can target a drilled cell |
| `commentary` | Text Editor | the narrative |
| `category` | Select | `Explanation\nRisk\nAction\nFX\nOne-off` |
| `status` | Select | `Draft\nReviewed\nApproved` (reuse Frappe workflow pattern) |

Uniqueness: one **active** commentary per `(data_area_id, fiscal_year, fiscal_period, main_account, scenario_compare, dimension_context)`; saving a new one supersedes (does not delete) the prior via `status`/`modified`, mirroring the budget audit pattern in `api.py`.

### 4. API + Excel retrieval

| Surface | Behaviour |
|---|---|
| `konsol/api.py` `variance_commentary_save()` | Upsert a commentary for a cell key (parallels `budget_cell_save()`); returns the saved doc with `modified` for optimistic-locking parity with budget cells |
| `konsol/api.py` `get_variance_with_commentary()` | Returns `gold_variance_analysis` rows joined to active `Variance Commentary` for the requested cells (left join — number always returned, `commentary` null if none) |
| `=EPM(... , "price_effect", ...)` / `volume_effect` / `mix_effect` | New measures resolve to `gold_variance_bridge`; validated against the Measure registry (PRD API Generalisation) |
| `=EPM(... , "pop_variance_abs"/"rolling_3m_avg", ...)` | New measures resolve to `gold_trend_analysis` |
| `=EPM_COMMENTARY("USMF", 2025, "FY", "4100")` | New VBA shortcut returning the active commentary text for a cell (mirrors `EPM_BUDGET`/`EPM_VARIANCE`) |

### 5. Cube.js semantic layer

| Artifact | Change |
|---|---|
| `cube/schema/VarianceBridge.js` | cube over `gold_variance_bridge`; measures `price_effect`, `volume_effect`, `mix_effect`; dims entity/year/period/account/cost_center/department |
| `cube/schema/TrendAnalysis.js` | cube over `gold_trend_analysis`; measures `pop_variance_abs`, `pop_variance_pct`, `rolling_3m_avg`, `rolling_12m_avg`; `seq_index` dimension for charts |
| `cube/schema/VarianceAnalysis.js` (existing) | add `has_commentary` boolean dimension fed by the commentary join |

## Out of Scope

- New statistical/quantity fact ingestion — `gold_variance_bridge` consumes whatever quantity facts the Fact Registry (Phase 2.3) already exposes; building those connectors is out of scope here. Accounts without quantity degrade to `price_only`.
- Consolidated/FX-translated bridges and trends beyond what `gold_trial_balance` / `gold_scenario_trial_balance` already provide (no new CTA handling).
- Multi-GAAP variance commentary (Phase 6.2) — commentary keys do not include `reporting_standard` yet.
- Rich charting/visualisation UI in Frappe Desk; this PRD delivers the data + API, not a dashboard.
- Threaded/multi-user discussion on a cell — commentary is single active narrative per cell, not a comment thread.

## Acceptance Criteria

1. `dbt build` produces `gold_variance_bridge` and `gold_trend_analysis`; the gold model count increases from 22 to 24 (report-catalog.md updated to match).
2. dbt test `assert_bridge_reconciles`: for every `gold_variance_bridge` row, `price_effect + volume_effect + mix_effect = variance_abs` within 0.01.
3. dbt test `assert_bridge_price_only_fallback`: rows with null `actual_qty` and null `budget_qty` have `bridge_method = 'price_only'`, `price_effect = variance_abs`, and `volume_effect = mix_effect = 0`.
4. dbt test `assert_pop_lag`: `prior_period_amount` for `(entity, account, year, period)` equals `period_net_amount` of the immediately preceding period in `gold_period_hierarchy` order; first period in a series has null `prior_period_amount`.
5. dbt test `assert_rolling_window_size`: `rolling_3m_avg` averages at most 3 and `rolling_12m_avg` at most 12 trailing periods, partitioned per `(entity, account, dims)`.
6. Saving a `Variance Commentary` creates exactly one active record for its cell key; saving a second for the same key leaves the first non-active and the new one active (no hard delete). pytest `test_variance_commentary_supersede` passes.
7. `get_variance_with_commentary()` returns every requested variance row; rows with an active commentary include the `commentary` text, rows without return `commentary = null` (left join, no dropped numbers).
8. `=EPM("USMF",2025,"FY","4100","price_effect","variance")` returns the bridge price effect; `=EPM_COMMENTARY("USMF",2025,"FY","4100")` returns the active narrative for that cell.
9. Cube query on `VarianceAnalysis` exposes `has_commentary = true` only for cells with an active `Variance Commentary`.

## Open Questions

- Bridge grain for **mix**: true mix effect is only meaningful across a product/dimension set. Should `mix_effect` be computed per individual dim member, or kept as the account-level residual (current default)? Residual guarantees reconciliation but blurs per-product mix.
- Which dimension carries "volume"? `gold_variance_bridge` assumes a single quantity measure per account; multi-driver accounts (price × volume × FX) may need a richer decomposition deferred to Planning Enhancements (Phase 6.8 driver-based planning).
- Commentary cell key vs. drilled dimensions: store `dimension_context` as opaque JSON (current default) or promote each budget dimension to its own column for indexable joins? JSON is flexible but cannot be joined in ClickHouse without expansion.
- Should `EPM_COMMENTARY` resolve commentary for period ranges (`Q1`, `FY`) by concatenating monthly narratives, or only return commentary stored at that exact period granularity?
