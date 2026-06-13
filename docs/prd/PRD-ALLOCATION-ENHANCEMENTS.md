# PRD: Allocation Enhancements (Circular & Reciprocal)

**Status:** Not Started
**Date:** 2026-06-13
**Phase:** Phase 6.7 — Analytical Gaps (Allocation Enhancements)
**Repos:** `konsolidat` (dbt/data stack), `konsol` (Frappe app — `run_allocation` API)

## Problem
- The dynamic N-step cascade engine (`macros/allocation_engine_multistep.sql`, PRD-17) handles **ordered step-down** allocations only. It explicitly excludes self-allocation (`assert_no_self_allocation`) and cannot represent **reciprocal cost pools** where, e.g., IT serves Facilities *and* Facilities serves IT.
- A reciprocal macro already exists — `macros/allocation_engine_reciprocal.sql` (PRD-18, iterative, `max_iterations = 10`, convergence cutoff `abs(feedback) > 0.01`) — but it is **dead code**: `gold_allocation_results.sql` only calls `allocation_engine_multistep()`. Reciprocal results never reach the gold model.
- Because of that, `tests/assert_reciprocal_converges.sql` references columns the gold model never emits (`final_iteration`) and tests `allocation_method = 'reciprocal'` rows that are never produced — so the test is effectively vacuous today.
- There is **no simultaneous-equations (matrix) method**. Iteration is the only intended approach, which is slow to converge and gives no exact answer for tightly-coupled pools. Controllers expect the textbook "reciprocal method" exact result.
- `allocation_rules.csv` seed has **no `allocation_method` column** (only `step_order`, `driver_type`, etc.), yet both macros and the convergence test already read `allocation_method` from `epm_staging.allocation_rules`. The seed and the source contract are out of sync.

## Solution
Wire the existing iterative reciprocal macro into `gold_allocation_results` alongside the step-down cascade, add an exact **simultaneous-equations** reciprocal method as a selectable alternative, and make `allocation_method` a first-class rule attribute. Reciprocal pools resolve first; their settled net amounts then feed the ordered step-down cascade.

## Scope

### 1. Rule contract — `allocation_method`
Add `allocation_method` to `seeds/allocation_rules.csv` and the `epm_staging.allocation_rules` source.

| Field | Type | Values | Default |
|---|---|---|---|
| `allocation_method` | String | `step_down`, `reciprocal`, `reciprocal_matrix` | `step_down` |
| `reciprocal_group` | String | groups mutually-allocating pools (e.g. `SERVICE_DEPTS`) | `''` |
| `max_iterations` | UInt8 | iteration cap for `reciprocal` (ignored for matrix) | `10` |
| `convergence_tolerance` | Float64 | residual cutoff (currency units) | `0.01` |

Rules with the same `reciprocal_group` are solved together as one coupled system. `step_down` rows keep current behaviour and `step_order`.

### 2. Iterative reciprocal — productionize PRD-18
- Promote `convergence_tolerance` / `max_iterations` from hard-coded literals to per-rule values read from the rule contract.
- Emit `iteration` and `final_iteration` columns through to gold (the convergence test depends on `final_iteration`).
- Emit `allocation_method = 'reciprocal'` and `converged` (Boolean: `final_iteration < max_iterations`) per `(allocation_rule_id, data_area_id, fiscal_year, fiscal_period)`.

### 3. Simultaneous-equations method — new macro `allocation_engine_reciprocal_matrix`
New file `macros/allocation_engine_reciprocal_matrix.sql`. For each `(reciprocal_group, data_area_id, fiscal_year, fiscal_period)`:
1. Build driver-weight coefficient matrix **A** (cost center → cost center share) and direct-cost vector **b** from `gold_trial_balance` pools.
2. Solve **(I − A)·x = b** for total cost vector **x** (settled department totals after receiving reciprocal services).
3. Distribute each settled total `x_i` to consuming cost centers by driver weight, excluding the in-group self-pool.

Implement the solve via Gauss-Jordan elimination unrolled in Jinja over `range(group_size)` (mirrors the existing Jinja-unrolled iteration pattern); cap `reciprocal_group` size at `max_group = 8` cost centers (Jinja-unrolled, like `max_steps = 20`). Output schema matches the iterative path with `allocation_method = 'reciprocal_matrix'`, `final_iteration = NULL`, `converged = true`.

### 4. Gold model — union all methods
Rewrite `models/gold/gold_allocation_results.sql` to UNION:

| Source macro | `allocation_method` |
|---|---|
| `allocation_engine_reciprocal()` | `reciprocal` |
| `allocation_engine_reciprocal_matrix()` | `reciprocal_matrix` |
| `allocation_engine_multistep()` | `step_down` |

Reciprocal macros run **before** step-down; the step-down cascade reads settled reciprocal net amounts as additional pool input (preserves the existing PRD-17 "later step sees prior allocations" semantics). Add `allocation_method`, `iteration`, `final_iteration`, `converged` to the gold column set documented in `allocation-guide.md`. Update `models/gold/_gold__models.yml` and `gold_allocation_audit_trail.sql` for the new columns.

### 5. API & docs
- `konsol.api.run_allocation` (`POST /api/method/konsol.api.run_allocation`) unchanged in signature; runs now span all three methods. Document method mix in `docs/api-reference/api-run-allocation.md`.
- Add a "Reciprocal & Circular Allocations" section to `docs/user-guide/allocation-guide.md` with a worked two-department reciprocal example showing iterative vs. matrix giving the same settled totals.

## Out of Scope
- Cross-period / multi-period reciprocal carryforward (each period solves independently).
- Cross-entity (`data_area_id`) reciprocal allocation — groups are solved within a single legal entity.
- New driver types — reuse `headcount`, `sqm`, `revenue` via `epm_staging.allocation_drivers` and `resolve_allocation_driver`.
- Cube.js semantic-layer measures and Excel `=EPM()` surfacing of method/convergence metadata (reporting follow-up).
- Reciprocal-group size beyond `max_group = 8` cost centers.

## Acceptance Criteria
1. `dbt seed` loads `allocation_rules.csv` with `allocation_method`, `reciprocal_group`, `max_iterations`, `convergence_tolerance` columns; existing 3 step-down rules default to `step_down`.
2. `gold_allocation_results` contains rows with `allocation_method` in (`step_down`, `reciprocal`, `reciprocal_matrix`) when reciprocal rules exist; `step_down`-only configs are byte-identical to pre-change output.
3. `tests/assert_reciprocal_converges.sql` passes against real reciprocal rows (`final_iteration` populated; late-iteration amount ≤ 1% of total).
4. New test `assert_reciprocal_matrix_settles`: for each `reciprocal_group`, `SUM(direct_cost) = SUM(allocated_amount to out-of-group cost centers)` within `convergence_tolerance` (no cost lost in the solve).
5. New test `assert_iterative_matches_matrix`: for a fixture group configured with both methods, settled department totals agree within `0.01` (proves iteration converges to the exact simultaneous-equations result).
6. `assert_each_step_sums_to_pool` and `assert_no_self_allocation` still pass for `step_down` rows (no regression on PRD-17 invariants).
7. `POST run_allocation` for a period with mixed methods returns `status = "Active"` and `gold_allocation_results` reflects all methods for that `allocation_run_id`.

## Open Questions
- Convergence failure handling: if `converged = false` after `max_iterations`, fail the dbt build, or surface a warning row and proceed? (Lean: warning + `converged` flag for downstream alerting.)
- Should `reciprocal_matrix` be the default when a `reciprocal_group` is set, with iteration kept only as a validation/fallback path?
- Negative driver totals within a reciprocal group make `(I − A)` ill-conditioned — reject at seed-validation time, or clamp like the revenue-driver `driver_value > 0` filter?
