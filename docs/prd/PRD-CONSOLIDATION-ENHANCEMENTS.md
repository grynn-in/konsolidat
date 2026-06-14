# PRD: Consolidation Enhancements

**Status:** Not Started
**Date:** 2026-06-13
**Phase:** Phase 6.6 — Analytical Gaps (Consolidation Enhancements)
**Repos:** `konsolidat` (dbt/data stack — gold consolidation models), `konsol` (Frappe app — source tables `ownership_periods`, `historical_equity_rates`, new `equity_transactions`)

## Problem
The consolidation engine already covers the base cases but stops short of the full IAS 21 / IFRS 3 / IFRS 10 acquisition-and-disposal mechanics:

- `gold_fx_revaluation` computes CTA only from the **P&L closing-vs-average spread** (`sum(local_amount × (closing_rate - average_rate) × ownership_pct)`, `is_equity = 0` excluded). It has **no CTA on goodwill** — goodwill recorded in foreign currency (`gold_acquisition_adjustments`, `adjustment_type='goodwill'`) is never re-translated, so the group BS does not balance for foreign acquisitions (IAS 21.47).
- CTA recycling on disposal (`gold_disposal_adjustments`, `adjustment_type='cta_recycling'`) recycles **only** the accumulated `cta_amount` from `gold_fx_revaluation`. Since goodwill CTA is not tracked, the recycled amount understates the IAS 21.48 reclassification.
- `historical_equity_rates` applies one historical rate per equity account but the rate is **not pinned to acquisition date** for the pre-acquisition equity of an acquired sub; there is no remeasurement-vs-translation distinction (`fx-translation.md` assumes a single functional currency).
- `gold_acquisition_adjustments` computes goodwill as `acquisition_price - net_assets × ownership%` (parent share only = **partial goodwill**). There is no **full goodwill** option (NCI measured at fair value), and `gold_nci_movement_schedule` carries a `consolidation_method` column but no goodwill-method dimension.
- There is no model for **changes in ownership without loss of control** (IFRS 10.23) — a parent buying/selling NCI while retaining control. Today an ownership % change flows through `ownership_periods` as if it were an acquisition/disposal, producing a spurious P&L gain instead of an equity transaction.

## Solution
Extend the existing acquisition/disposal/CTA/NCI gold models (not new parallel models) to: (1) translate goodwill at closing rate and book goodwill CTA into `gold_fx_revaluation`; (2) add a `goodwill_method` (full/partial) driver to acquisition + NCI models; (3) add a functional-currency / remeasurement flag for non-translation cases; (4) add a `gold_equity_transactions` model and `equity_transactions` source for ownership changes without loss of control.

## Scope

### 1. New & extended source contracts (`konsol` → `epm_staging`)
Add columns to existing sources and one new source table. All are Frappe-doctype-backed, synced to ClickHouse `epm_staging` (same path as `ownership_periods`, `historical_equity_rates`).

| Source | Field | Type | Purpose |
|---|---|---|---|
| `ownership_periods` (extend) | `goodwill_method` | String `'full'`\|`'partial'` | full vs partial goodwill (IFRS 3.19); default `'partial'` |
| `ownership_periods` (extend) | `nci_fair_value` | Float | NCI fair value at acquisition (required when `goodwill_method='full'`) |
| `consolidation_groups` (extend) | `functional_currency` | String | enables remeasurement vs translation test (IAS 21) |
| `historical_equity_rates` (extend) | `is_acquisition_date_rate` | UInt8 | flags the acquisition-date rate row used to pin pre-acquisition equity |
| `equity_transactions` (new) | `consolidation_group`, `data_area_id`, `transaction_date`, `ownership_pct_before`, `ownership_pct_after`, `consideration_amount` | — | ownership change without loss of control |

Register `equity_transactions` in `models/staging/_staging__sources.yml` under `epm_staging` (mirror the `ownership_periods` entry, `loaded_at_field: updated_at`).

### 2. Goodwill translation & goodwill CTA (`gold_fx_revaluation.sql`)
Add a second CTA component alongside the existing P&L component.

| Output column / term | Definition |
|---|---|
| `goodwill_local` | goodwill in sub functional currency = `adjustment_amount` from `gold_acquisition_adjustments` where `adjustment_type='goodwill'` |
| `goodwill_cta_component` | `goodwill_local × (closing_rate - prior_closing_rate) × ownership_pct` (IAS 21.47) |
| `pnl_cta_component` | unchanged (existing) |
| `cta_amount` | `pnl_cta_component + goodwill_cta_component` |

Goodwill CTA is `0` when `accounting_currency = reporting_currency`. Keep one CTA row per `consolidation_group, data_area_id, fiscal_year, fiscal_period` (existing grain) — add `goodwill_cta_component` as a breakout column for audit/recycling.

### 3. Full vs partial goodwill (`gold_acquisition_adjustments.sql`, `gold_nci_movement_schedule.sql`)
In the `goodwill` CTE, branch on `ownership_periods.goodwill_method`:

| Method | `goodwill_amount` |
|---|---|
| `partial` (default, current behaviour) | `acquisition_price - (net_assets × ownership_pct/100)` |
| `full` | `(acquisition_price + nci_fair_value) - net_assets` |

Add `nci_goodwill_amount = goodwill_amount - parent_goodwill` to `gold_nci_movement_schedule` (non-zero only for `goodwill_method='full'`), as a new opening component in the movement reconciliation.

### 4. Remeasurement vs translation distinction (`gold_consolidated_trial_balance.sql`)
Add `is_remeasured` flag: `1` when `consolidation_groups.functional_currency = reporting_currency` but `accounting_currency != functional_currency` (temporal/remeasurement method — gains to P&L, no CTA); `0` for current-rate translation (gains to CTA/OCI). When `is_remeasured = 1`, route the FX gain to a P&L line (`main_account='RM'`, `adjustment_type='remeasurement'`) instead of CTA, and exclude those entities from `gold_fx_revaluation` CTA.

### 5. Acquisition-date equity rate pinning (`gold_consolidated_trial_balance.sql`)
Extend the existing `historical_rates` lookup (lines ~71-78, 242-260): when an equity row belongs to a sub with an `ownership_periods.acquisition_date`, select the `historical_equity_rates` row flagged `is_acquisition_date_rate=1` for pre-acquisition equity; post-acquisition movements keep latest-rate-≤-period logic. `translation_rate` and downstream `group_amount`/`nci_amount` formulas unchanged.

### 6. Changes in ownership without loss of control (`gold_equity_transactions.sql` — new gold model)
Equity transaction (no gain/loss to P&L; adjustment to parent equity per IFRS 10.B96):

```
nci_transferred = nci_bs_total × (ownership_pct_after - ownership_pct_before) / nci_pct_before
equity_adjustment = consideration_amount - nci_transferred
```

Output grain: one row per `consolidation_group, data_area_id, fiscal_year, fiscal_period` derived from `transaction_date`, with `adjustment_type='equity_transaction'`, `main_account='EQ_TXN'`, columns `equity_adjustment`, `nci_transferred`. `nci_bs_total` sourced from `gold_nci_movement_schedule.nci_closing_balance`. Rows where the sub appears in `ownership_periods` with `is_disposal=1` (loss of control) are excluded — those stay in `gold_disposal_adjustments`.

### 7. Wiring into consolidated output
Add `gold_equity_transactions` and the new `remeasurement` / `goodwill_cta` lines to `gold_consolidation_adjustments` (the model that unions topside adjustment sources) so they flow into `gold_consolidated_trial_balance` and the Cube `consolidated_trial_balance` schema. No new Cube measures required — entries reuse existing `adjustment_amount` / `group_amount` measures.

## Out of Scope
- Loss-of-control disposals (full deconsolidation) — already covered by `gold_disposal_adjustments` (PRD-12).
- Step acquisitions remeasuring previously-held interest to fair value (IFRS 3.42) — separate enhancement.
- Hyperinflationary economies (IAS 29) restatement.
- Hedge of a net investment in a foreign operation (IAS 21.32 / IFRS 9 net-investment hedging).
- Multi-GAAP parallel goodwill (covered by Phase 6.2 `reporting_standard` dimension).
- Frappe doctype UI/form design for the new source fields (data contract only here).

## Acceptance Criteria
1. `dbt build` produces the same model count plus exactly **one** new model (`gold_equity_transactions`); `gold_acquisition_adjustments`, `gold_disposal_adjustments`, `gold_fx_revaluation`, `gold_nci_movement_schedule`, `gold_consolidated_trial_balance` are modified in place (no new parallel CTA/goodwill models).
2. New singular test `assert_goodwill_cta_when_foreign`: for any `goodwill` entry where `accounting_currency != reporting_currency` and `closing_rate != prior_closing_rate`, `gold_fx_revaluation.goodwill_cta_component != 0`.
3. New singular test `assert_goodwill_cta_zero_same_currency`: `goodwill_cta_component = 0` for all rows where `accounting_currency = reporting_currency` (mirrors `assert_cta_zero_for_same_currency`).
4. Existing `assert_cta_recycled_on_disposal` still passes, and recycled amount now equals `-(pnl_cta_component + goodwill_cta_component)` summed to disposal date.
5. New singular test `assert_full_goodwill_includes_nci`: where `goodwill_method='full'`, `gold_nci_movement_schedule.nci_goodwill_amount != 0`; where `'partial'`, it is `0`.
6. New singular test `assert_equity_transaction_no_pnl`: rows in `gold_equity_transactions` never appear in `gold_disposal_adjustments` with `adjustment_type='disposal_gain_loss'` for the same group/date (no spurious P&L).
7. New singular test `assert_remeasurement_excluded_from_cta`: entities with `is_remeasured=1` have no row in `gold_fx_revaluation` (FX gain went to P&L `RM` line instead).
8. `assert_consolidated_bs_balances_with_cta` still passes for a foreign acquisition fixture including goodwill (group BS nets to 0 within 0.01 tolerance with goodwill CTA included).
9. Existing tests unchanged: `assert_cta_zero_for_same_currency`, `assert_equity_historical_no_cta`, `assert_nci_movement_reconciles`, `assert_nci_plus_group_equals_translated`, `assert_goodwill_calculated`, `assert_cta_not_zero_when_rates_differ` all still pass.
10. `equity_transactions` registered as an `epm_staging` source in `_staging__sources.yml` and resolvable via `{{ source('epm_staging', 'equity_transactions') }}`.

## Open Questions
- Goodwill CTA grain: track cumulatively per acquisition (so partial disposals recycle proportionally) or per-period delta like P&L CTA? Per-period is simpler and matches the existing `gold_fx_revaluation` grain; cumulative is needed if step disposals are added later.
- Should `full` vs `partial` goodwill be selectable per acquisition (`ownership_periods.goodwill_method`) or fixed per reporting standard? IFRS 3 allows per-transaction choice; defaulting per-acquisition is assumed here.
- Remeasurement (temporal method) requires a non-monetary-vs-monetary account classification to apply historical vs closing rates within the BS. Reuse `is_equity` + a new `is_monetary` flag on `silver_main_accounts`, or defer full temporal method to a follow-up?
- `equity_transactions` consideration currency: assume reporting currency, or translate at transaction-date rate like acquisition price?
