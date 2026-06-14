# PRD: Planning Enhancements (Driver-Based & Recurring)

**Status:** Not Started
**Date:** 2026-06-13
**Phase:** Phase 6.8 — Analytical Gaps
**Repos:** `konsolidat` (dbt/data stack), `konsol` (Frappe app)

## Problem

- Budget input today is amount-only. `Budget Input` captures an `annual_amount` spread across 12 periods via `Spread Profile` weights (`gold_spread_budget.sql`), but there is no way to plan revenue as **price × volume** — planners cannot flex volume independently of rate, so re-planning a price change means re-keying every cell.
- Spreading is global per submission: `spread_profiles.csv` keys only on `profile_id` + `fiscal_period`. There is no notion of applying a seasonal pattern **by account group** (e.g. all revenue accounts get retail seasonality, all payroll accounts get even), so each planner picks a profile per line manually.
- Topside journals are entered by hand. `Consolidation Adjustment` (`is_submittable`, ClickHouse `epm_staging.consolidation_adjustments`) supports one-off entries with an `auto_reverse_period` field, but recurring monthly accruals (depreciation, amortization, standing reclasses) must be re-posted every period — there is no template that auto-generates them on a schedule.
- Approval is conflated. `Consolidation Adjustment Workflow` gates every transition on `System Manager` only; there is no journal-specific approver tier, and the Phase 6.5 budget chain (`budget_input_workflow.json`) is a separate document type. Topside journals need their own controller/CFO sign-off distinct from budget approval.

## Solution

Add (1) a driver-based revenue model that decomposes plan lines into `price × volume` and feeds the existing budget staging path; (2) account-group phasing templates that auto-select a `Spread Profile` per account group; (3) a `Recurring Journal Template` doctype + scheduled job that generates `Consolidation Adjustment` docs each period; and (4) a dedicated topside-journal approval workflow with journal-specific roles, replacing the System-Manager-only transitions.

## Scope

### 1. Driver-based planning (`konsol` + `konsolidat`)

New `Driver Plan` parent doctype (module EPM) with child `Driver Plan Line`, mirroring the top-down/bottom-up split in `budget_input.py`.

| Doctype | Field | Type | Notes |
|---------|-------|------|-------|
| Driver Plan | `scenario_id` | Link Scenario Definition | reuses existing scenario registry |
| Driver Plan | `data_area_id` | Data | legal entity |
| Driver Plan | `fiscal_year` | Int | |
| Driver Plan | `main_account` | Data | revenue account |
| Driver Plan Line | `fiscal_period` | Int | 1–12 |
| Driver Plan Line | `volume` | Float | units |
| Driver Plan Line | `price` | Currency | rate per unit |
| Driver Plan Line | `amount` | Currency | computed `volume × price`, read-only |

- On `validate`, compute `amount = volume × price` per line (parallels `_compute_annual_amount`).
- On approval, write 12 period rows to `epm_staging.budget_input` (existing staging) tagged `input_method = 'driver'`, so `gold_scenario_trial_balance` picks them up with zero dbt changes — consistent with the budget-spreading "API does the spreading into staging" decision.
- New dbt model `gold_driver_plan.sql` (gold layer) materializes `price`, `volume`, `period_amount` for variance bridges (consumed later by Phase 6.9 waterfall). Add `tests` asserting `period_amount = price * volume`.

### 2. Account-group phasing templates (`konsolidat`)

New seed `phasing_templates.csv` mapping account groups to a spread profile:

```csv
account_group,profile_id
REVENUE,SEASONAL_RETAIL
PAYROLL,EVEN
OPEX,EVEN
```

- New seed `account_groups.csv` (`main_account_from`, `main_account_to`, `account_group`) defines ranges; or reuse an existing account-mapping seed if present.
- New dbt model `gold_phased_budget.sql`: for annual inputs **without** an explicit `spread_profile_id`, resolve the profile by joining the account's group → `phasing_templates` → `spread_profiles`, then apply the same normalized-weight logic as `gold_spread_budget.sql`. Explicit per-line profiles still win.
- `Spread Profile` doctype gains optional `account_group` field so templates are editable in Frappe Desk and synced to the seed/ClickHouse.

### 3. Recurring journal templates (`konsol`)

New `Recurring Journal Template` doctype (module Consolidation), child `Recurring Journal Line` (same line shape as `Consolidation Adjustment`: `data_area_id`, `main_account`, `debit_amount`, `credit_amount`, `description`).

| Field | Type | Notes |
|-------|------|-------|
| `template_name` | Data | |
| `consolidation_group` | Data | |
| `adjustment_type` | Select | `topside` / `reclassification` (matches existing options) |
| `frequency` | Select | `monthly` / `quarterly` |
| `start_period` / `end_period` | Int | active window |
| `auto_reverse` | Check | sets generated doc's `auto_reverse_period = 1` |
| `is_active` | Check | |

- New scheduler hook in `konsol/hooks.py` — `scheduler_events["monthly"]` calls `generate_recurring_journals()`, which for each active template in-window creates a `Consolidation Adjustment` with a deterministic `journal_id` (e.g. `RJ-{template_name}-{fiscal_year}-{fiscal_period}`) and `status = "Pending Approval"`.
- Idempotent: skip if a `Consolidation Adjustment` with that `journal_id` already exists, so re-runs do not double-post.
- Generated docs flow through the workflow in §4 (not auto-approved), then sync to `epm_staging.consolidation_adjustments` via the existing `on_update` path.

### 4. Topside journal approval workflow (`konsol`)

Replace the System-Manager-only `consolidation_adjustment_workflow.json` with a journal-specific chain on the existing `status` field (`workflow_state_field` stays `status`).

| State | `doc_status` | `allow_edit` |
|-------|--------------|--------------|
| Draft | 0 | Journal Preparer |
| Pending Approval | 0 | Journal Approver |
| Approved | 1 | (none — locked) |
| Reversed | 2 | (none) |

| From | Action | To | `allowed` |
|------|--------|----|-----------|
| Draft | Submit for Approval | Pending Approval | Journal Preparer |
| Pending Approval | Approve | Approved | Journal Approver |
| Pending Approval | Reject | Draft | Journal Approver |
| Approved | Reverse | Reversed | Journal Approver |

- New Frappe roles `Journal Preparer`, `Journal Approver` (distinct from `Budget *` roles). Set `doc_status: 1` only on `Approved` so submit fires there; reconcile `ConsolidationAdjustment.on_submit` (which currently flips `Draft → Pending Approval`) to the workflow transitions.
- `validate` already stamps `approved_by` / `approved_at` when `status == "Approved"` — keep.
- Ship workflow + roles + email `Notification` fixtures (await-approval to `Journal Approver`, approved/rejected to `posted_by`), mirroring the Phase 6.5 notification pattern.

## Out of Scope

- Multi-tier (controller → CFO) topside approval — single Preparer → Approver tier here; deeper chains deferred.
- Driver hierarchies beyond `price × volume` (e.g. volume = headcount × productivity); only the two-factor decomposition.
- Mix/rate variance reporting — that is Phase 6.9 (waterfall/bridge); this PRD only emits the driver facts it will consume.
- Rolling-forecast auto-spread (Phase 6.3) and budget cell locking (Phase 6.4).
- Changes to budget approval (`budget_input_workflow.json`) — that chain is owned by Phase 6.5.

## Acceptance Criteria

1. `dbt build` runs `gold_driver_plan`, `gold_phased_budget` in addition to existing models; `dbt ls` returns the two new gold models.
2. dbt test `assert_driver_amount_equals_price_x_volume` passes: every `gold_driver_plan` row has `period_amount = price * volume` within 0.01.
3. Approving a `Driver Plan` writes exactly 12 rows per `main_account` to `epm_staging.budget_input` with `input_method = 'driver'`; they appear in `gold_scenario_trial_balance`.
4. For an annual input with no `spread_profile_id`, `gold_phased_budget` resolves the profile via `account_groups` → `phasing_templates` and the 12 period amounts sum to `annual_amount` within 0.01 (`assert_phased_spread_sums_to_annual`).
5. An explicit per-line `spread_profile_id` overrides the account-group template.
6. Running `generate_recurring_journals()` for an active monthly template creates one `Consolidation Adjustment` per in-window period in `Pending Approval`; a second run creates no duplicates (same `journal_id`).
7. `consolidation_adjustment_workflow.json` loads via `bench migrate` with the 4 states / 4 transitions above; a `Journal Preparer` can Submit but the Approve action is not offered to them.
8. `Approve` sets `docstatus == 1` and locks the doc; reaching `Approved` syncs to `epm_staging.consolidation_adjustments` exactly once and emails `posted_by`.
9. pytest `test_recurring_journal_idempotent` and `test_driver_plan_staging_write` pass.

## Open Questions

- Should `account_groups` reuse an existing account-classification seed (e.g. cash-flow categories) rather than introduce a new range seed?
- Does driver-based planning need its own scenario type (e.g. `driver`) in `scenario_definitions.csv`, or is `input_method` on the staging rows sufficient?
- Auto-reversal of recurring journals: generate the reversal as a separate `Consolidation Adjustment` (next period) or rely on the existing `auto_reverse_period` mechanism on the generated doc?
- Should `Journal Approver` collapse into the Phase 6.5 `Budget Controller` role to avoid role proliferation, or stay strictly separate?
