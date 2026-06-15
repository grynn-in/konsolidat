# PRD: Budget Cell Locking (Concurrency Control)

**Status:** Not Started
**Date:** 2026-06-13
**Phase:** Phase 6.4 — Analytical Gaps
**Repos:** `konsol` (Frappe app — API, doctypes, `schema_apply.py`, `Dimension` registry, migration patch), Excel add-in (VBA `=EPM()` / `EPMSAVE()`)

**Scope note:** revised from locking-only to **grain + permission + locking**. The concurrency fix is now secondary to correcting the budget doc grain (dimensional, derived from the `in_budget` registry) and enforcing write-path permissions; see [Grain & Permission Model](#grain--permission-model).

## Problem

`konsol.api.budget_cell_save()` is a blind last-write-wins upsert. It loads the Budget Input doc, mutates one `(fiscal_period, layer)` row in the `periods` child table, and calls `doc.save()` — with no check that the caller's view of the cell is still current:

- Two analysts editing the same `(scenario_id, data_area_id, fiscal_year, main_account)` Budget Input doc silently overwrite each other. Frappe's own `modified` timestamp guard does not protect `EPMSAVE()` because the client never sends a baseline `modified`.
- A single `budget_cell_save()` rewrites the **whole doc**, so two cells in different periods of the same account collide even though they are logically independent.
- Excel has no way to detect a stale write — the user sees `{"status": "ok"}` and assumes their number stuck when it was clobbered seconds later.
- There is no way to reserve a cell/account during a long edit session; controllers locking a budget for review have no concurrency primitive.

**Root cause is the doc grain, not just a missing staleness check.** The upsert key `_budget_filters()` is `(scenario_id, data_area_id, fiscal_year, main_account)` — it **drops every budget dimension**. The `in_budget` dimensions (`dim_cost_center`, `dim_department`, …) are carried only as **parent attributes the last writer stamps**, and the `periods` child grain is `(fiscal_period, amount, layer)` with no dimension. So two writers who differ *only* by cost center collapse onto the **same doc** and clobber — and no permission scheme can separate them, because there is nothing to separate at the doc level. This contradicts the app's own design: the `Dimension` registry has an `in_budget` flag, and `schema_apply.py` already provisions a Custom Field on Budget Input per `in_budget` Published dimension. The dimensional model is declared but **not honoured by the storage key**. Optimistic locking layered on this grain only converts silent clobbers into noisy false-conflicts; the grain must be corrected first (see [Grain & Permission Model](#grain--permission-model) below).

## Grain & Permission Model

> This section supersedes the doc-level grain assumed by the original locking-only design. The doctype/API references below (`_budget_filters`, `Budget Lock` granularity, the doc-level Open Questions) are reframed accordingly.

### What budgeting practice actually requires

Budget granularity is **account-type-dependent**, so neither "account only" (today) nor a hardcoded "account + cost center" is correct:

| P&L / BS slice | Planned by cost center? | Planned by… |
|---|---|---|
| Revenue / sales | No | Product, customer/channel, region, or **profit center** |
| COGS | Sometimes | Product / plant (cost center in manufacturing) |
| **Operating expenses** (personnel, T&E, facilities) | **Yes — the norm** | **Cost center = department = budget owner** (responsibility/departmental budgeting) |
| Below-the-line (interest, tax, D&A) | No | Central / entity level |
| Balance sheet | Never | Entity / legal entity |

The consequence: "different owners budget different cost centers of the **same** account" is **not an edge case — it is the dominant operating-expense pattern** (every department head budgets their slice of the shared `Salaries` / `Travel` account, keyed by their cost center). Revenue and BS, by contrast, are planned with **no** cost center. The dimension *set* therefore varies by account type and by org — which is exactly why the dimension set must be **data-driven, not hardcoded**.

### Decision: derive the budget grain from the `in_budget` registry

The budget unique key becomes **dynamic**, sourced from the `Dimension` registry rather than a fixed tuple:

```
(scenario_id, data_area_id, fiscal_year, main_account, *<all Dimension where in_budget=1 and status="Published">)
```

This needs **zero code change per added dimension**: flag a dimension `in_budget=1`, `schema_apply.py` already provisions its Budget Input field, and the key picks it up automatically. Revenue rows leave cost center blank and carry product/region; opex rows carry cost center. A single flat `in_budget` set with a consistent blank/sentinel for non-applicable dimensions is the MVP (per-account-type or per-scenario dimensionality can come later).

### Decision: one doc per full dimensional combination (Option A)

Two ways to realise the dynamic grain; the choice is dictated by ownership and concurrency:

| | **Option A — doc per full combination (CHOSEN)** | Option B — dimensions on the periods child |
|---|---|---|
| Doc key | scenario, LE, FY, account, **+ all `in_budget` dims** | scenario, LE, FY, account (dims move into child rows) |
| One doc represents | one owner's cell-set for one combination | all dimensional breakdowns of an account, mixed owners |
| Permission / ownership | **doc = ownership boundary**; User Permissions on LE / account-group / dim cleanly separate owners | one shared doc → permission cannot separate co-owners |
| Concurrency (this PRD) | different owners ⇒ **different docs ⇒ no contention** | same doc ⇒ clobber/lock problem persists |
| Doc count | more docs, but **sparse** (only planned combinations exist) | fewer docs |

**Option A is chosen.** It makes *the dimensional combination = the unit of ownership = the unit of concurrency*, so permissions and the optimistic-lock safety net operate at the same natural grain and reinforce each other. The "same account, different cost center" case dissolves: those are now distinct docs, separable by permission and contention-free.

Implementation deltas:
- `_budget_filters()` returns the fixed keys **plus** every `in_budget` Published dimension value from the request (defaulting missing dims to `""`).
- Add a **unique constraint / unique-index** on the full key set (via doctype `unique` on a composite, or an idempotent guard in the upsert) so two requests for the same combination converge on one doc.
- `budget_cell_save()` / `budget_save()` / `budget_save_batch()` resolve the same dynamic key. The `periods` child grain is unchanged (`fiscal_period, amount, layer`) — dimensions live on the parent.
- Backfill/migration: existing Budget Input rows already carry the dimension values as parent attributes, so a patch can re-key them in place; collisions (pre-existing rows that shared a key) must be surfaced, not silently merged.

### Permission model (Frappe-native, reuses the existing entity-authz pattern)

The merged security work already built the right primitive in `konsol/api.py`: `_entity_permission_doctype()` (configured via `EPM Settings.entity_permission_doctype`) → `_resolve_allowed_entities()` reads the user's **native Frappe User Permissions** for that doctype → `_assert_entity_access(entity)` enforces. It is applied on the **read** path (`epm_value`, `epm_batch`) but **not** on the budget **write** path.

| Ownership level | Mechanism | Status |
|---|---|---|
| **Legal entity** (`data_area_id`) — "1 user owns 1 / a few LEs" | `_assert_entity_access(data["data_area_id"])` in the budget write endpoints | **Reuse existing pattern; apply to writes** (small) |
| **Main account** (by group/range, e.g. a controller owns all `6xxx`) | New `EPM Settings.account_permission_doctype` (an *Account Responsibility* / account-group doctype) + `_assert_account_access(account)` mirroring `_resolve_allowed_entities`; gate by **group, never per-individual-account** (per-value User Permissions don't scale) | **New, same pattern** |
| **Finer dimensions** (cost center, etc.) — only if ownership is split below account | Gate by **group** via User Permissions, or a server-side `permission_query_condition` reading a responsibility-mapping doctype | **Optional; only when a customer splits ownership below account** |

These compose by **AND**: a write to `(LE=FR, account=6100, cc=…)` must pass the entity check *and* the account-group check (*and* any finer-dim check). `data_area_id` and `main_account` are `Data` fields (not `Link`), which is why permissions key on a **dedicated permission-target doctype + code match** (the established pattern) rather than native Link-based User Permissions.

### How this reframes the locking design (below)

With LE + account-group partitioning, two users almost never share a writable doc, so **optimistic locking drops from the primary mechanism to a thin safety net** for the genuine-overlap case (e.g. a controller and their analyst both authorised on FR/revenue). Concretely:
- The optimistic `base_modified` check (§1) **stays** — it is correct and cheap — but is no longer the hot path.
- A short row lock (`frappe.db.get_value(..., for_update=True)` on the resolved doc before mutate) serialises the rare same-doc concurrent writers, eliminating the read-modify-write race outright.
- The **pessimistic `Budget Lock` doctype (§2) is deferred** — not needed for early EPM once permissions partition ownership. It remains specified below for completeness but moves to "build only if same-doc contention is observed in practice."

## Solution

Add **optimistic locking** to `budget_cell_save()`: the client sends the `modified` timestamp it last read; the server rejects stale writes with a `409`-style conflict payload carrying the current cell value so the VBA add-in can re-prompt. Add an **optional pessimistic `Budget Lock` doctype** (5-minute auto-expiry) for explicit reservations. VBA retries on conflict by refreshing the cell and re-asking the user.

## Scope

> **Build order:** the grain and permission items below (§A, §B) **precede** the locking work (§1–§3) — they are the corrective foundation; the original §1–§3 are retained with their numbering because they are cross-referenced above.

### A. Dynamic dimensional grain (`konsol/api.py`, migration)

- Rewrite `_budget_filters(data)` to return the fixed keys **plus every `Dimension` where `in_budget=1 and status="Published"`**, defaulting missing dimension values to `""`. All three write endpoints resolve through it.
- Enforce uniqueness on the full key set (doctype composite `unique`, or an idempotent upsert guard) so one combination ⇒ one doc.
- Migration patch: re-key existing Budget Input rows from their parent dimension attributes; **surface, do not silently merge**, any rows that collided under the old account-only key.

### B. Write-path permission enforcement (`konsol/api.py`, new doctype)

- Apply `_assert_entity_access(data["data_area_id"])` in `budget_cell_save()`, `budget_save()`, `budget_save_batch()` (reuses the existing read-path pattern).
- Add `EPM Settings.account_permission_doctype` + an *Account Responsibility* (account-group) doctype + `_assert_account_access(account)` mirroring `_resolve_allowed_entities`; gate by group. Skipped when unset (backward-compatible).
- Optional finer-dim gating via `permission_query_condition` — only if a customer splits ownership below account.

### 1. Optimistic locking on `budget_cell_save()` (`konsol/api.py`)

Add two optional request params; behaviour is backward-compatible when both are omitted (current last-write-wins preserved).

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `base_modified` | string (datetime) | No | The doc `modified` the client last read. If set and stale, reject. |
| `base_amount` | number | No | The cell amount the client last read. Used for conflict diff/echo. |

Behaviour:

- Resolve the Budget Input doc via the **corrected dynamic `_budget_filters(data)`** (fixed keys + all `in_budget` dimensions — see [Grain & Permission Model](#grain--permission-model)). Take a `for_update` row lock on the resolved doc before mutating to serialise the rare same-doc writers. If the doc exists and `base_modified` is supplied and `str(doc.modified) != base_modified`, **do not save** — return a conflict.
- Enforce write permission **before** mutating: `_assert_entity_access(data["data_area_id"])` and (when configured) `_assert_account_access(data["main_account"])`. A write to an LE/account the caller does not own returns `frappe.PermissionError` (HTTP 403), not a conflict.
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

### 2. `Budget Lock` doctype (optional pessimistic mode — DEFERRED) (`konsol/epm/doctype/budget_lock/`)

> **Deferred per [Grain & Permission Model](#grain--permission-model).** Once LE + account-group permissions partition ownership and the grain is one doc per full dimensional combination (Option A), same-doc contention is rare and the optimistic check + `for_update` row lock cover it. Build this only if same-doc contention is observed in practice. Specification retained below for completeness.

Autoname `BLOCK-.#####`. Granularity = the **full dynamic Budget Input key** (one lock per dimensional-combination doc — i.e. the fixed keys plus all `in_budget` dimensions), matching the corrected upsert unit.

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

- Per-cell (period+layer) row-level `modified` tracking — locking granularity is the (now dimensional-combination) Budget Input doc, matching the corrected upsert unit. Note this is *finer* than today precisely because the grain now includes the `in_budget` dimensions; sub-doc period/layer locking remains out of scope.
- Per-account-type or per-scenario **dimension sets** — the MVP uses a single flat `in_budget` set with blank/sentinel for non-applicable dimensions; conditional dimensionality is a later enhancement.
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
9. **Grain:** two `budget_cell_save()` calls for the same `(scenario, LE, FY, account)` but **different `dim_cost_center`** create/update **two distinct Budget Input docs**; neither clobbers the other's periods. (Today they collide on one doc.)
10. **Grain is dynamic:** flagging an additional `Dimension` as `in_budget=1` (and republishing) makes it part of the upsert key with no code change — a save differing only by that new dimension resolves to a separate doc.
11. **Permission (LE):** `budget_cell_save()` / `budget_save()` / `budget_save_batch()` for a `data_area_id` the caller lacks a User Permission for raise `PermissionError` (403) and write nothing; an owned LE succeeds. System Manager / Administrator bypass (parity with the read path).
12. **Permission (account):** with `EPM Settings.account_permission_doctype` configured, a write to an account outside the caller's responsibility group is rejected (403); an in-group account succeeds. With it unset, account checks are skipped (backward-compatible).

## Open Questions

- Should a successful optimistic save by a different period/layer of the same doc invalidate another client's `base_modified` (since the whole-doc `modified` bumps on any cell write)? Likely yes — accept the false-positive conflict for now, since the client retry refreshes cleanly. Revisit if it causes excessive re-prompts. *(Now lower-impact: the dimensional grain means a "doc" is one owner's combination, so cross-period false-conflicts are within a single owner's own session.)*
- **Grain migration collisions:** existing Budget Input rows that shared the old `(scenario, LE, FY, account)` key but differ on dimensions must be re-keyed. Some pre-existing rows may already have clobbered each other under the old grain — how should the patch surface (not silently merge) any irrecoverable collisions?
- **Account-group permission target:** there is no chart-of-accounts doctype in the app today (accounts are `Data` + a dbt seed). Should the *Account Responsibility* doctype model groups/ranges explicitly, or derive groups from the account-hierarchy seed? Determines whether `_assert_account_access` resolves account→group at runtime or via a maintained mapping.
- **Finer-dim ownership:** do any target customers split ownership *below* the account (e.g. per cost center)? If not, ship LE + account-group only and leave the dimension-level `permission_query_condition` unbuilt.
- *(Resolved — was: keep lock at doc level vs. add period/layer scoping.)* Lock granularity is the full dimensional-combination doc; sub-doc scoping is out of scope. The pessimistic lock itself is deferred.
- Should `expires_at` renew on every `budget_cell_save()` by the lock holder (sliding window), or only on explicit `budget_lock_acquire`? *(Only relevant if the deferred pessimistic mode is built.)*
