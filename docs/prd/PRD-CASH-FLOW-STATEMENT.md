# PRD: Cash Flow Statement (Indirect Method)

**Status:** Not Started
**Date:** 2026-06-13
**Phase:** Phase 6.1 — Analytical Gaps
**Repos:** `konsolidat` (dbt/data stack)

## Problem

- The gold layer ships P&L (`gold_pnl_by_period`) and balance sheet (`gold_balance_sheet`, `gold_bs_movement`) models, but there is **no cash flow statement** — the third primary financial statement is missing from the platform.
- `gold_bs_movement` already computes per-account `opening_balance`, `period_movement`, `closing_balance`. The deltas needed for an indirect cash flow exist but are never categorized into Operating / Investing / Financing or reconciled to the change in cash.
- Consolidated reporting (`gold_consolidated_trial_balance`, `gold_fully_consolidated_tb`) handles FX translation, IC elimination, CTA, and topside adjustments, but offers no consolidated cash flow. There is no way to show group cash generated/consumed after translation.
- No seed maps GL accounts to cash flow categories, so balance-sheet movements cannot be classified.

## Solution

Add `gold_cash_flow_indirect.sql`, deriving the statement from balance-sheet account movements (delta method): start from net income, classify every BS account's `period_movement` into Operating / Investing / Financing via a new `cash_flow_categories.csv` seed, and reconcile the three category totals to the period change in cash. Add a consolidated variant built on the FX-translated consolidation models.

## Scope

### 1. Seed: `cash_flow_categories.csv`

Maps each GL account to a cash flow category and sign treatment. Lives in `seeds/`, loaded to `epm_gold` via `dbt seed` (12th seed file).

| Column | Type | Description |
|--------|------|-------------|
| `main_account` | String | GL account |
| `cf_category` | String | `Operating`, `Investing`, or `Financing` |
| `cf_line_item` | String | Sub-line label (e.g. `Change in Receivables`, `CapEx`, `Dividends Paid`) |
| `is_cash` | UInt8 | 1 = this account *is* cash/cash-equivalent (excluded from activity, used for reconciliation) |
| `sign` | Int8 | `+1` or `−1` — converts a BS movement into its cash effect (asset increase = cash outflow) |

Default rows cover seeded accounts: cash (`is_cash=1`), receivables/payables/inventory → Operating; fixed-asset & IC investment accounts → Investing; debt, equity (3xxx), IC dividend (8100) → Financing.

### 2. Entity model: `gold_cash_flow_indirect.sql`

dbt model in `models/gold/`, materialized as the entity-level statement. Grain: one row per `data_area_id` × `fiscal_year` × `fiscal_period` × `cf_category` × `cf_line_item`.

| Column | Type | Description |
|--------|------|-------------|
| `data_area_id` | String | Legal entity |
| `fiscal_year` | UInt16 | Fiscal year |
| `fiscal_period` | UInt8 | Fiscal period |
| `cf_category` | String | `Operating` / `Investing` / `Financing` |
| `cf_line_item` | String | Sub-line label from seed |
| `main_account` | String | Source account (blank for the net-income line) |
| `cash_flow_amount` | Decimal | Cash effect = `period_movement × sign` |

Logic:
- Join `gold_bs_movement` to `cash_flow_categories` on `main_account`; exclude `is_cash = 1` accounts from activity lines.
- Operating starts with net income (sum of P&L `period_net_amount` from `gold_pnl_by_period`) plus working-capital movements.
- `cash_flow_amount = period_movement × sign` per categorized line.
- Net change in cash = `−Σ(cash_flow_amount)` of activity lines = `Σ period_movement` over `is_cash = 1` accounts.

### 3. Consolidated model: `gold_consolidated_cash_flow.sql`

Group-level statement built **after FX translation**, sourced from `gold_fully_consolidated_tb` (entity + IC elimination + CTA + topside layers). Grain adds `consolidation_group`; drops `data_area_id` to a group rollup. Movements derive from consecutive-period deltas of `amount` per `main_account`, then categorized identically via the seed. CTA-driven movement of cash is reported as a non-cash reconciling line so the statement still ties to the change in translated cash.

### 4. Documentation

Add `gold_cash_flow_indirect` and `gold_consolidated_cash_flow` to `docs/data-dictionary/gold-models.md`; add `cash_flow_categories.csv` to `docs/data-dictionary/seeds-reference.md`; add a "Cash Flow Statement" section to `docs/user-guide/consolidation-guide.md`.

## Out of Scope

- Direct-method cash flow (gross receipts/payments from sub-ledgers).
- Sub-ledger-driven detail (AP/AR/Fixed Assets facts from Phase 2.3) — this PRD uses BS movements only.
- Cube.js measures / Excel `=EPM()` exposure and any Frappe `konsol` API or doctype work.
- Multi-GAAP cash flow variants (Phase 6.2) and rolling-forecast cash flow (Phase 6.3).

## Acceptance Criteria

1. `dbt seed` loads `cash_flow_categories.csv` into `epm_gold`; seed count goes from 11 to 12.
2. `dbt build` produces `gold_cash_flow_indirect` and `gold_consolidated_cash_flow` with no errors.
3. Every categorized row has `cf_category` ∈ {`Operating`,`Investing`,`Financing`} (dbt `accepted_values` test).
4. **Reconciliation test** `assert_cf_categories_equal_net_change` passes: per `data_area_id`/`fiscal_year`/`fiscal_period`, `Σ Operating + Σ Investing + Σ Financing = net change in cash` (movement of `is_cash = 1` accounts), within ±0.01.
5. The same reconciliation test passes at group grain for `gold_consolidated_cash_flow` per `consolidation_group`/period.
6. `dbt test` relationship test confirms every non-cash `main_account` in `gold_bs_movement` has a matching row in `cash_flow_categories` (no uncategorized accounts).
7. Consolidated cash flow uses FX-translated amounts: for a multi-currency group, totals differ from the simple sum of entity local-currency cash flows.

## Open Questions

- Should net income for the operating section be pulled from `gold_pnl_by_period` (period) or `gold_consolidated_ytd` for the consolidated variant, to avoid double-counting cumulative vs. periodic figures?
- How are CTA and IC-elimination layers in `gold_fully_consolidated_tb` treated — fold into a single "FX/consolidation reconciling" line, or split per category?
- Do period-1 movements need a prior-year closing balance as opening, or is the year-open balance assumed flat?
