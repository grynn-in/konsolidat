# PRD: Multi-Step Budget Approval Chain

**Status:** Not Started
**Date:** 2026-06-13
**Phase:** Phase 6.5 — Analytical Gaps
**Repos:** `konsol` (Frappe app)

## Problem

- The current `Budget Input Workflow` (`budget_input_workflow.json`) is a flat two-tier approval: `Draft → Submitted → Approved/Rejected`. A single `Budget Approver` role approves in one step. Real budget cycles require sequential sign-off (dept manager → controller → CFO), and there is no audit trail of who approved at which tier.
- Nothing locks an approved budget. The `Budget Input` doctype has no `is_submittable` flag and `workflow_state` is a plain `Data` field, so an approved doc can still be edited (only `_validate_layer_permissions` gates by layer role). `docstatus` stays `0` at every state, so "Approved" is not immutable.
- The only side effect on approval is `on_update` calling `_sync_to_clickhouse()` when `workflow_state == "Approved"` — that string must keep working as the warehouse-sync trigger as states are renamed.
- No notifications: approvers are not told when a budget is waiting on them, so the chain stalls silently.

## Solution

Replace the flat workflow with a five-state sequential chain in `budget_input_workflow.json`, each transition gated by a distinct Frappe role; make `Budget Input` submittable so the final CFO approval sets `docstatus = 1` and permanently locks the document; and fire Frappe `Notification` emails on each state change.

## Scope

### 1. Workflow states (`budget_input_workflow.json`)

Replace `states[]`. `doc_status` is the Frappe submit status the workflow forces on entering the state.

| State | `doc_status` | `allow_edit` |
|-------|--------------|--------------|
| Draft | 0 | Budget Submitter |
| Submitted | 0 | Budget Controller |
| Dept Manager Approved | 0 | Budget Manager |
| Controller Approved | 0 | Budget Controller |
| CFO Approved | 1 | (none — locked) |
| Rejected | 0 | Budget Submitter |

`workflow_state_field` stays `workflow_state`.

### 2. Transitions

Each `allowed` is a single, distinct role. Every approval-bearing state also gets a `Reject` transition back to `Rejected`.

| From | Action | To | `allowed` |
|------|--------|----|-----------|
| Draft | Submit for Review | Submitted | Budget Submitter |
| Submitted | Dept Manager Approve | Dept Manager Approved | Budget Manager |
| Submitted | Reject | Rejected | Budget Manager |
| Dept Manager Approved | Controller Approve | Controller Approved | Budget Controller |
| Dept Manager Approved | Reject | Rejected | Budget Controller |
| Controller Approved | CFO Approve | CFO Approved | Budget Approver |
| Controller Approved | Reject | Rejected | Budget Approver |
| Rejected | Resubmit | Submitted | Budget Submitter |

`Budget Approver` is reused as the CFO tier (no new role needed); `Budget Manager` becomes the dept-manager tier. All four roles (`Budget Submitter`, `Budget Controller`, `Budget Manager`, `Budget Approver`) already exist in `LAYER_ROLES` in `budget_input.py`.

### 3. Lock on final approval

- Set `"is_submittable": 1` in `budget_input.json` so `docstatus` is meaningful.
- Entering `CFO Approved` carries `doc_status: 1` → Frappe submits the doc; all fields become read-only and edits require an amend/cancel. This is the permanent lock required by Phase 6.5.
- Keep the ClickHouse sync trigger working: change the gate in `BudgetInput.on_update` from `workflow_state == "Approved"` to `workflow_state == "CFO Approved"` (final-approval sync), so only fully approved budgets reach the warehouse.

### 4. Email notifications (Frappe `Notification` doctype)

One `Notification` doc per hand-off, `document_type = Budget Input`, `event = Value Change`, `value_changed = workflow_state`, channel Email.

| Notification | Condition (`workflow_state ==`) | Recipients |
|--------------|----------------------------------|-----------|
| Budget awaiting Dept Manager | `Submitted` | role Budget Manager |
| Budget awaiting Controller | `Dept Manager Approved` | role Budget Controller |
| Budget awaiting CFO | `Controller Approved` | role Budget Approver |
| Budget fully approved | `CFO Approved` | `submitted_by` |
| Budget rejected | `Rejected` | `submitted_by` |

Ship these as fixtures so they install with the app. Subject/message reference `scenario_id`, `data_area_id`, and `fiscal_year`.

### 5. Backward compatibility

- Existing `Budget Input` docs in the old `Approved` state must be migrated. Add a patch (`konsol/patches.txt`) that renames `workflow_state` `Approved → CFO Approved` and sets `docstatus = 1` for those docs.
- `budget-layers.md` (Budget Layers Guide) references the old workflow; update its approval section to the five-state chain.

## Out of Scope

- Topside journal approval workflow (Phase 6.8 — separate from budget approval).
- Configurable / dynamic approval tiers per legal entity or amount threshold (delegation, escalation, auto-approve under a limit).
- In-app or Slack notifications — email only, via the `Notification` doctype.
- Changes to the dbt budget models, spread profiles, or `EPM_BUDGET` Excel functions.
- Parallel approvals (e.g., two managers in any order) — the chain is strictly sequential.

## Acceptance Criteria

1. `budget_input_workflow.json` defines exactly 6 states and 8 transitions matching the tables above; `bench migrate` loads the workflow with `is_active = 1`.
2. `budget_input.json` has `"is_submittable": 1`.
3. A `Budget Submitter` can move Draft → Submitted but cannot perform any approval action; the `Dept Manager Approve` action is not offered to them.
4. The CFO Approve action (role `Budget Approver`) moves the doc to `CFO Approved` and sets `docstatus == 1`; the document is then read-only and cannot be edited without amend.
5. Reaching `CFO Approved` triggers `_sync_to_clickhouse()` exactly once; reaching any intermediate approval state does not sync.
6. Saving each intermediate state sends the matching `Notification` email to the correct role; reaching `CFO Approved` / `Rejected` emails `submitted_by`.
7. A `Reject` from any approval state returns the doc to `Rejected`, and `Resubmit` returns it to `Submitted`.
8. Migration patch upgrades all pre-existing `Approved` docs to `CFO Approved` with `docstatus = 1`; no doc is left in the deprecated `Approved` state.

## Open Questions

- Should `Budget Controller` (per the old workflow's `Submitted.allow_edit`) be permitted to edit while a doc sits in `Submitted`, or only the dept-manager tier act on it? Current table keeps `allow_edit: Budget Controller` on `Submitted` for parity.
- Is a separate dedicated CFO role wanted, or is reusing `Budget Approver` as the final tier acceptable long-term?
- On `Reject`, should the doc reset to `Draft` (full restart) instead of `Rejected → Resubmit → Submitted` (re-enter at submission)? Current design preserves the existing reject/resubmit loop.
