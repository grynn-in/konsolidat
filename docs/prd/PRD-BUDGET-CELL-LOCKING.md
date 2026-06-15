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
| **Main account** (by category, e.g. a controller owns all of *Travel*) | `EPM Settings.account_permission_doctype` → a **Virtual DocType `Main Account Category`** proxying `silver_main_accounts.main_account_category` live from ClickHouse (no synced copy); `_assert_account_access(account)` resolves account→category via a **cached** map and checks User Permission, mirroring `_resolve_allowed_entities`. Gate by **category, never per-individual-account**. | **New, same pattern, virtual proxy** |
| **Cost center** (and other in_budget dims) — ownership split *below* the account | **Required** (confirmed: a *Travel* account is booked by multiple departments/cost centers). Virtual DocType `Cost Center` (proxying the dimension values from CH) as the permission target; `_assert_dimension_access(dim, value)` enforces at cost-center grain. Generalises to any in_budget dimension flagged ownership-controlling. | **New, required** |

These compose by **AND**: a write to `(LE=FR, account=Travel, cc=Sales)` must pass the entity check *and* the account-category check *and* the cost-center check. `data_area_id`, `main_account`, and the dimension values are `Data` fields (not `Link`), which is why permissions key on a **dedicated permission-target doctype + code match** (the established pattern) rather than native Link-based User Permissions.

**Virtual DocType as the permission target (Frappe v15.93).** The category/cost-center masters live in the dbt/ClickHouse layer, not in Frappe. Rather than syncing copies, model the permission targets as **Virtual DocTypes** (`is_virtual: 1`) whose read-only controller (`get_list`/`load_from_db`) serves values live from CH via `konsol.clickhouse.execute()`. This works because **Frappe User Permission rows live in the real `tabUser Permission` table regardless of whether the *target* doctype is virtual** — a grant is just `(user, allow="Main Account Category", for_value="Travel")`, a string our `_assert_*` code reads exactly like the entity pattern. Two constraints:
- **No automatic SQL filtering on virtual doctypes** — Frappe's `permission_query_condition` injects a `WHERE` into a MariaDB query that does not exist for a virtual doctype. Harmless here because enforcement is hand-rolled in `api.py`, but it means the generic machinery gives no free enforcement; the check must be explicit in code.
- **Never resolve on a live CH round-trip in the write path** — `account→category` (and `account/cc` validity) is needed on every `budget_cell_save`. Cache the resolver map in `frappe.cache()` with a TTL (small, slow-changing data); the live virtual doctype is for the *picker/browse* UX only, not the per-cell hot path.

**Future-proofing — Frappe v16.** Verified against the v16 (`develop`) source and the official [Migrating to version 16](https://github.com/frappe/frappe/wiki/Migrating-to-version-16) guide:
- **Virtual DocType is not in the v16 breaking-changes list.** The controller contract is unchanged: a controller must override `db_insert`, `db_update`, `load_from_db`, `delete` (instance) and define static `get_list`, `get_count`, `get_stats`. Our targets are read-only, so the write methods are stubs that `raise frappe.ValidationError` — same as v15.
- **User Permission / `get_user_permissions` mechanics are not in the v16 breaking-changes list.** Critically, User Permission `validate()` does **not** require `for_value` to be a real row (it only checks duplicate/overlap), and `get_user_permissions` already tolerates a missing target table — so a virtual-doctype permission target works in both v15 and v16.
- **The two v16 permission breaking changes only affect `has_permission` *hooks*** (`has_permission` hooks must now return explicit `True`; `frappe.permissions.has_permission` drops `raise_exception` for `print_logs`). **We avoid them by design** — enforcement is explicit `_assert_*` calls that raise `PermissionError`, not registered hooks.
- **Avoid "Apply to All Document Types" User Permissions** — they have reported rough edges in v16 (report-filter false positives) and are semantically wrong here anyway; scope every grant to its specific permission-target doctype.

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

### B. Write-path permission enforcement (`konsol/api.py`, Virtual DocTypes)

- Apply `_assert_entity_access(data["data_area_id"])` in `budget_cell_save()`, `budget_save()`, `budget_save_batch()` (reuses the existing read-path pattern).
- **Account (by category):** add `EPM Settings.account_permission_doctype` → a **Virtual DocType `Main Account Category`** proxying `silver_main_accounts.main_account_category` live from ClickHouse (no synced copy); `_assert_account_access(account)` resolves account→category via a **`frappe.cache()`-backed map** and checks User Permission. Skipped when unset (backward-compatible).
- **Cost center (REQUIRED — confirmed: *Travel* booked by multiple departments):** Virtual DocType `Cost Center` proxy as permission target; `_assert_dimension_access(dim, value)` enforces at cost-center grain. Generalises to any in_budget dimension flagged ownership-controlling.
- Enforce in **explicit code** (`_assert_*`), not Frappe `has_permission` hooks — virtual doctypes get no automatic SQL permission filtering, and this also sidesteps the v16 `has_permission`-hook contract change (see Future-proofing note).

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

## Resolved Decisions

1. **Grain migration collisions → non-issue.** No customer is live; the Budget Input table holds only demo/empty data. The patch re-keys in place with **no collision-recovery path**; it keeps a defensive guard that *errors loudly* if a real collision is ever encountered, but none is expected.
2. **Account permission target → Virtual DocType, derived live (not a hand-maintained master).** No Frappe chart-of-accounts doctype exists, but the grouping exists in the warehouse as `silver_main_accounts.main_account_category` (from D365 `MainAccountCategory`). Model `Main Account Category` as a **Virtual DocType** proxying CH live; resolve account→category via a `frappe.cache()`-backed map. No sync job, always current.
3. **Finer-dim ownership → REQUIRED, build it.** Confirmed: a *Travel* main account is booked by multiple departments (cost centers), each owning only their slice. Enforce at **cost-center grain** via a `Cost Center` Virtual DocType permission target + `_assert_dimension_access`. Generalises to any in_budget dimension flagged ownership-controlling.
4. **v16 future-proof** (see Future-proofing note): the Virtual-DocType-as-permission-target + explicit `_assert_*` enforcement is unaffected by v16's permission-hook breaking changes.

## Open Questions

- Should a successful optimistic save by a different period/layer of the same doc invalidate another client's `base_modified` (since the whole-doc `modified` bumps on any cell write)? Likely yes — accept the false-positive conflict for now, since the client retry refreshes cleanly. *(Low-impact: a "doc" is now one owner's combination, so cross-period false-conflicts stay within a single owner's own session.)*
- Which in_budget dimensions beyond cost center are **ownership-controlling** vs. merely descriptive? (Cost center is confirmed; department/product/region TBD per customer — drives how many Virtual DocType permission targets ship.)
- *(Resolved — lock granularity is the full dimensional-combination doc; sub-doc scoping out of scope; pessimistic lock deferred.)*
- Should `expires_at` renew on every `budget_cell_save()` by the lock holder (sliding window), or only on explicit `budget_lock_acquire`? *(Only relevant if the deferred pessimistic mode is built.)*
