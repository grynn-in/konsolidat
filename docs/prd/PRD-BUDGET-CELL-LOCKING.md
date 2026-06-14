# PRD: Budget Cell Locking (Concurrency Control)

**Status:** Not Started
**Date:** 2026-06-13
**Phase:** Phase 6.4 — Analytical Gaps
**Repos:** `konsol` (Frappe app — API + doctypes), Excel add-in (VBA `=EPM()` / `EPMSAVE()`)

## Problem

`konsol.api.budget_cell_save()` is a blind last-write-wins upsert. It loads the Budget Input doc, mutates one `(fiscal_period, layer)` row in the `periods` child table, and calls `doc.save()` — with no check that the caller's view of the cell is still current:

- Two analysts editing the same `(scenario_id, data_area_id, fiscal_year, main_account)` Budget Input doc silently overwrite each other. Frappe's own `modified` timestamp guard does not protect `EPMSAVE()` because the client never sends a baseline `modified`.
- A single `budget_cell_save()` rewrites the **whole doc**, so two cells in different periods of the same account collide even though they are logically independent.
- Excel has no way to detect a stale write — the user sees `{"status": "ok"}` and assumes their number stuck when it was clobbered seconds later.
- There is no way to reserve a cell/account during a long edit session; controllers locking a budget for review have no concurrency primitive.

## Solution

Add **optimistic locking** to `budget_cell_save()`: the client sends the `modified` timestamp it last read; the server rejects stale writes with a `409`-style conflict payload carrying the current cell value so the VBA add-in can re-prompt. Add an **optional pessimistic `Budget Lock` doctype** (5-minute auto-expiry) for explicit reservations. VBA retries on conflict by refreshing the cell and re-asking the user.

## Scope

### 1. Optimistic locking on `budget_cell_save()` (`konsol/api.py`)

Add two optional request params; behaviour is backward-compatible when both are omitted (current last-write-wins preserved).

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `base_modified` | string (datetime) | No | The doc `modified` the client last read. If set and stale, reject. |
| `base_amount` | number | No | The cell amount the client last read. Used for conflict diff/echo. |

Behaviour:

- Resolve the Budget Input doc via existing `_budget_filters(data)`. If the doc exists and `base_modified` is supplied and `str(doc.modified) != base_modified`, **do not save** — return a conflict.
- Conflict response (HTTP 409 via `frappe.local.response.http_status_code = 409`):

  ```json
  {
    "status": "conflict",
    "name": "BUD-BUDGET_2025-USMF-2025-6100",
    "fiscal_period": 3, "layer": "base",
    "your_amount": 15000,
    "current_amount": 17500,
    "current_modified": "2026-06-13 09:41:22.512000"
  }
  ```

  `current_amount` is read from the matching `periods` row (or `0` if the row does not yet exist).
- On success, echo the new baseline so the client can store it without a re-read:

  ```json
  { "status": "ok", "name": "...", "value": 15000, "modified": "2026-06-13 09:42:10.001000" }
  ```

- Re-read the doc inside the same request right before the staleness check (`frappe.get_doc` already returns the committed row) to minimise the check→save window. Wrap the load+save in the request's transaction; no extra commit.

### 2. `Budget Lock` doctype (optional pessimistic mode) (`konsol/epm/doctype/budget_lock/`)

Autoname `BLOCK-.#####`. Granularity = the Budget Input key (one lock per account doc), matching the upsert unit.

| Field | Type | Notes |
|-------|------|-------|
| `scenario_id` | Data | part of lock key |
| `data_area_id` | Data | part of lock key |
| `fiscal_year` | Int | part of lock key |
| `main_account` | Data | part of lock key |
| `locked_by` | Link → User | defaults to `frappe.session.user` |
| `locked_at` | Datetime | set on acquire |
| `expires_at` | Datetime | `locked_at + 5 min` |

New whitelisted endpoints (`methods=["POST"]`) in `konsol/api.py`:

| Method | Behaviour |
|--------|-----------|
| `konsol.api.budget_lock_acquire` | Acquire/renew lock for the key. Fail if a non-expired lock is held by another user; return holder + `expires_at`. |
| `konsol.api.budget_lock_release` | Release a lock held by the caller. |

- `budget_cell_save()` checks for an active (`expires_at > now`) `Budget Lock` on the key held by **another** user and rejects with `status: "locked"` + holder + `expires_at`. The caller's own lock (or no lock) is allowed.
- Expiry is lazy: a lock with `expires_at <= now_datetime()` is treated as free (and may be deleted on acquire). A scheduled `frappe.utils.scheduler` daily/hourly job purges expired `Budget Lock` rows.
- Pessimistic mode is gated by a single flag `EPM Settings.budget_pessimistic_locking` (default off); optimistic locking is always on.

### 3. VBA retry on conflict (Excel add-in)

- `EPMSAVE()` caches `base_modified` + `base_amount` per cell from the last `=EPM()` retrieve or prior save echo, and sends them on save.
- On `status: "conflict"`: refresh the cell to `current_amount`, show a prompt ("Value changed to X by another user — overwrite with your Y?"). On overwrite, resend with the new `current_modified` as `base_modified` (single retry); on cancel, leave the server value.
- On `status: "locked"`: surface holder + minutes-until-`expires_at`; do not write.
- Bound retries (max 1 automatic re-prompt cycle) to avoid loops.

## Out of Scope

- Per-cell (period+layer) row-level `modified` tracking — locking granularity is the Budget Input doc, matching today's upsert unit.
- Real-time presence/co-editing indicators or websocket push of other users' edits.
- Locking for `budget_save()` / `budget_save_batch()` bulk endpoints (cell-save is the interactive path; batch remains last-write-wins).
- Workflow-state locking (Submitted/Approved docs) — covered by Phase 6.5 multi-step approval and Frappe `docstatus`.
- ClickHouse/gold-layer concurrency; this PRD is the Frappe write-back path only.

## Acceptance Criteria

1. `budget_cell_save()` with no `base_modified` behaves exactly as today (upsert succeeds, returns `status: "ok"` plus a new `modified` field).
2. `budget_cell_save()` with a stale `base_modified` returns `status: "conflict"`, HTTP 409, and includes `current_amount` and `current_modified`; the stored doc is **unchanged** (no row mutated).
3. `budget_cell_save()` with a matching `base_modified` succeeds and the echoed `modified` equals the saved doc's new `modified`.
4. With `budget_pessimistic_locking` on, `budget_lock_acquire` for an unlocked key returns the lock with `expires_at == locked_at + 300s`; a second acquire by a different user returns `status: "locked"` + the first holder.
5. A `Budget Lock` whose `expires_at` is in the past is treated as free: `budget_lock_acquire` by any user succeeds and `budget_cell_save()` does not reject.
6. With an active lock held by user A, `budget_cell_save()` by user B returns `status: "locked"`; by user A succeeds.
7. The scheduled purge job deletes only `Budget Lock` rows with `expires_at <= now`; active locks survive.
8. pytest: a test simulating two clients (read same `modified`, both write) asserts the second write is rejected, not silently overwritten.

## Open Questions

- Should a successful optimistic save by a different period/layer of the same doc invalidate another client's `base_modified` (since the whole-doc `modified` bumps on any cell write)? Likely yes — accept the false-positive conflict for now, since the client retry refreshes cleanly. Revisit if it causes excessive re-prompts.
- Lock granularity: keep at doc level, or add optional `fiscal_period`/`layer` scoping to `Budget Lock` if contention within an account proves common?
- Should `expires_at` renew on every `budget_cell_save()` by the lock holder (sliding window), or only on explicit `budget_lock_acquire`?
