# PRD: Demo Data Source & Source-of-Truth Hygiene

**Status:** Design — ready for implementation
**Date:** 2026-06-15
**Phase:** Phase 3 — Multi-ERP / Source-of-Truth Hygiene
**Repos:** `konsol` (fixtures, `dbt_config.py`, `install.py`), `konsolidat` (dbt staging models, seeds, CI)

> All decisions resolved (see Resolved Decisions). Code to be implemented separately.

## Problem

A fresh Konsolidat install has an **empty connector registry** (0 `Connector` docs), so the
data pipeline has no real source of truth for which ERP adapters to union. Three concrete
defects fall out of this today:

1. **`erp_sources` is a hardcoded fallback, not a derived value.** `konsol/dbt_config.py:243`
   does `erp_sources = _build_erp_sources_vars() or ["d365_fo"]`. With no connectors the build
   targets `d365_fo` — an ERP that has **no data** in a clean install — so the demo/onboarding
   pipeline produces empty gold models. The dbt template carries the same hidden default:
   `stg_gl_entries.sql:15` → `{% set erp_sources = var('erp_sources', ['d365_fo']) %}`.

2. **The fallback masks a broken edge.** Because the registry always falls back to a non-empty
   list, the canonical staging models (`models/staging/canonical/*.sql`, 7 files) never have to
   handle an **empty `erp_sources`**. The union is `{% for erp in erp_sources %} … union all`;
   with `[]` that compiles to `with unioned as ( )` → invalid SQL. Any design that lets the user
   drain the registry (the desired flow below) trips this.

3. **Missing fixtures at the Frappe↔dbt seam.** `konsol/hooks.py` declares both `Connector` and
   `Dimension Mapping` as fixtures, but **neither `connector.json` nor `dimension_mapping.json`
   exists** in `konsol/fixtures/`. So:
   - No connector ships by default (root of defect #1).
   - The `dimension_mappings` crosswalk has no source-of-truth docs, yet `konsol/install.py`
     `after_migrate` calls `_regenerate_dimension_mappings_seed()` **unconditionally** — which
     rebuilds `dbt_project/seeds/dimension_mappings.csv` from the (zero) published docs and can
     **silently overwrite the committed 2-row crosswalk with an empty file**.

We want a clean default: a fresh install is a **working end-to-end demo** with zero external
configuration, real ERPs are added deliberately, and the user can retire the demo source once a
real source is live — with the build regenerating correctly at every step.

## Solution

Introduce a first-class, seeded **`demo_data`** ERP source that ships enabled by default, replacing
the hardcoded `d365_fo` fallback. Make Frappe docs/fixtures the single source of truth for both
the connector registry and the dimension crosswalk, and make the dbt canonical layer robust to an
empty source set so the demo source can be deleted safely.

> **Why a connector, not the standalone `clickhouse/demo-data.sql`?** That script (already on `main`)
> only loads rows into `epm_raw` — it leaves defect #1 (the hardcoded `erp_sources` fallback) **unfixed**
> and bypasses the connector registry + harmonization path, so it can't double as an integration
> smoke-test. The `demo_data` connector makes `erp_sources` truly registry-derived (the actual fix) and
> can **reuse the same seed rows** as that script. *(Decision: `demo_data` connector — the standalone
> script alone was considered and rejected.)*

**Lifecycle (target):**
1. Fresh install → `demo_data` connector exists & enabled (fixture) → `erp_sources: [demo_data]`
   → demo seeds flow through `staging/demo_data` → bronze/silver/gold populated. App is usable
   immediately.
2. User configures a real connector (e.g. ERPNext) in Frappe → `Connector.on_update` →
   `regenerate_vars()` → `erp_sources: [demo_data, erpnext]`.
3. User deletes `demo_data` in Frappe → `Connector.on_trash` → `regenerate_vars()` →
   `erp_sources: [erpnext]` → next governed build drops all demo rows.

The lifecycle plumbing already exists — `konsol/pipeline/doctype/connector/connector.py:32–41`
calls `regenerate_vars()` from both `on_update` and `on_trash`. This PRD feeds it a principled
default and removes the failure modes around the empty set.

> **Decisions** are consolidated in one place — see **[Resolved Decisions](#resolved-decisions-2026-06-15)** below. (An earlier draft carried a duplicate, separately-numbered "Decisions (locked)" block; it has been merged here to remove the conflicting numbering.)

## Scope

### 1. `demo_data` as a first-class source (konsol + dbt)
- Add `demo_data` to the `Connector.erp_type` Select options (currently
  `d365_fo, d365_bc, sap_s4, sap_ecc, sap_b1, erpnext` — no demo value).
- Ship **`konsol/fixtures/connector.json`**: one `Connector`, `erp_type=demo_data`, `enabled=1`,
  with the legal entities used by the demo seeds.
- Add a **`models/staging/demo_data/`** adapter producing the canonical column set (mirror the
  shape the existing `staging/d365_fo` and `staging/erpnext` adapters emit; the canonical
  contract is the column list consumed in `stg_gl_entries.sql`).
- Demo transactional data is sourced from the existing **seeds** (GL / budget / driver CSVs).

### 2. Make `erp_sources` truly registry-derived (konsol)
- Change `konsol/dbt_config.py` `regenerate_vars()` from `… or ["d365_fo"]` to `… or []`.
  The `demo_data` connector — not a hardcoded string — supplies the default value; when the user
  has deleted every connector, `erp_sources` is legitimately empty.
- Decide and document the dbt-template default in `var('erp_sources', …)` calls (recommended:
  `[]`, paired with the guard in §3, so behaviour is identical whether the var is empty or absent).

### 3. Empty-union guard in canonical staging (dbt) — **required**
- Update the 7 `models/staging/canonical/*.sql` models so an empty `erp_sources` compiles to a
  typed, zero-row result (e.g. `select … where 1=0` / `limit 0`) instead of `with unioned as ( )`.
- This is the safety net that makes "delete the last source" non-breaking; it is not optional once
  §2 removes the `d365_fo` mask.

### 4. Dimension Mapping crosswalk — source of truth + safety (konsol + dbt)  *(decided — see [Resolved Decisions](#resolved-decisions-2026-06-15))*
- **DECIDED — Frappe is the source of truth**: ship **`konsol/fixtures/dimension_mapping.json`**; treat
  `dbt_project/seeds/dimension_mappings.csv` as a **generated artifact** of
  `_regenerate_dimension_mappings_seed()` (never hand-edited / committed-by-hand).
- **DECIDED — the fixture is the safety, not a guard.** Shipping `dimension_mapping.json` means fixtures
  load **before** `after_migrate` runs `_regenerate_dimension_mappings_seed()`, so a fresh migrate always
  has published docs and regenerates a correct, **non-empty** crosswalk — this, not a no-op guard, is what
  prevents the committed CSV being emptied. An empty crosswalk (0 docs) is a **valid** state — "no mappings,
  everything passes through", per the regenerator's own contract — so it is deliberately **not** guarded
  against; clearing all mappings legitimately yields an empty seed. *(This supersedes an earlier draft that
  proposed no-op-on-0-docs, which contradicted the regenerator's documented behaviour.)*
- **Provide demo_data crosswalk rows**: harmonization joins on `erp_source`
  (`dim_harmonize_joins('unioned.erp_source', …)` in `stg_gl_entries.sql`). Either (a) author the
  demo seeds as already-canonical (no `demo_data` crosswalk rows needed), or (b) ship `demo_data`
  rows in the Dimension Mapping fixture. **Decided (Resolved Decision #1): raw demo values + ship
  `demo_data` crosswalk rows**, so the demo exercises harmonization.

### 5. Generated-artifact policy (docs)
- Document that `dbt_project/dbt_project.yml` `vars` and `seeds/dimension_mappings.csv` are
  **generated** from the Frappe registry (Dimension / Measure / Connector / Dimension Mapping
  doctypes shipped as fixtures). The fixtures are committed; the generated files are regenerate-on-
  migrate mirrors. **Decided (Resolved Decision #2): keep them tracked, but CI-enforce that they
  equal regenerate-from-fixtures** (the regenerator gains a build-from-fixtures mode). Workflow:
  edit in Frappe → `bench export-fixtures` → regenerate → commit; CI fails if the committed file
  drifts from the fixtures.

### 6. Phased path to add-on modularity (future)
- Long-term, real ERPs (`d365_fo`, `erpnext`, `sap_*`) should ship as **add-ons**, leaving only
  `demo_data` in core. The hard part: each adapter is **dbt SQL in the data-stack repo**
  (`models/staging/d365_fo/` ×16, `models/staging/erpnext/` ×7), not in the Frappe app. A true
  add-on must deliver *both* halves: the Frappe connector config (+ `erp_type` option) **and** the
  dbt adapter — cleanly modelled as **one dbt package per ERP** (`packages.yml` / `dbt deps`) plus
  its connector. This PRD does **not** implement that extraction; it only ensures core ships a
  self-contained `demo_data` so the extraction becomes possible later.

## Out of Scope
- Extracting existing `d365_fo` / `erpnext` adapters into separate dbt packages / Frappe add-ons
  (§6 is design intent only; deferred).
- Any change to bronze/silver/gold model logic beyond the canonical empty-union guard.
- Build-governance flow changes (demo data still builds via the existing governed `dbt build`).
- New demo content authoring beyond wiring the existing seeds to the `demo_data` adapter.

## Acceptance Criteria
1. A clean install (`down -v` → `deploy.sh`) yields `erp_sources: [demo_data]` **derived from a
   shipped, enabled `demo_data` connector** — not from any hardcoded fallback.
2. Gold models are **non-empty** on a fresh install with no external connector configured.
3. Adding a real connector in Frappe updates `erp_sources` to include it (existing `on_update`
   path) without manual YAML edits.
4. Deleting the `demo_data` connector in Frappe updates `erp_sources` to exclude it; if it was the
   last connector, `erp_sources` is `[]` and the **canonical models still compile and run**
   (zero rows), the build does not error.
5. `konsol/fixtures/connector.json` and `konsol/fixtures/dimension_mapping.json` exist and load on
   migrate; `bench export-fixtures` round-trips them without loss.
6. The shipped `dimension_mapping.json` fixture loads **before** `after_migrate`, so a fresh migrate
   regenerates a **non-empty** `dimension_mappings.csv` matching the fixture (the committed crosswalk is
   never silently emptied). Conversely, clearing all Dimension Mapping docs regenerates an **empty**
   crosswalk **without error** (empty = "everything passes through").
7. `demo_data` rows carry **un-harmonized source values** that reach gold **correctly harmonized**
   via the shipped `demo_data` crosswalk rows (Decision #1) — verifiable via `=EPM()`.
8. Docs state which files are generated vs source-of-truth and the regenerate→commit workflow.
9. **CI sync check (Decision #2):** a CI/pre-commit step regenerates `dbt_project.yml` vars +
   `dimension_mappings.csv` **from the committed fixtures** and fails if either committed file
   differs. (Requires the regenerator's build-from-fixtures mode.)
10. **Warn on last delete (Decision #3):** deleting the last enabled connector shows a non-blocking
    warning; the operation still succeeds and the build still runs (empty gold).
11. **Canonical contract (Decision #5):** a documented column-set contract exists and a dbt schema
    test asserts every `staging/<erp>` adapter (incl. `demo_data`) emits it; CI fails on violation.
12. **Template defaults (Decision #4):** no `var('erp_sources', …)` call carries a non-`[]` default.

## Resolved Decisions (2026-06-15)

Unifying principle: **Frappe fixtures are the single source of truth; every dbt artifact (`vars`,
the crosswalk CSV) is a generated mirror, never hand-managed. "Empty" is a valid, guarded state.
Defer modularity, but lock the interface now.**

1. **Demo crosswalk → ship raw demo values + a small `demo_data` crosswalk.** Author the demo seeds
   with *un-harmonized* source values and ship `demo_data` rows in `dimension_mapping.json` so the
   demo flows through the real harmonization path. *Why:* the demo doubles as a living example of
   dimension mapping **and** an integration smoke-test that fails loudly on harmonization
   regressions. (Cost is a handful of fixture rows.)

2. **Generated-file tracking → keep `dbt_project.yml` + `dimension_mappings.csv` TRACKED, but
   CI-enforce that they equal `regenerate-from-fixtures`.** Add a check (CI / pre-commit) that
   regenerates the vars + crosswalk **from the committed fixtures** and fails if the committed files
   differ. *Why:* keeps the dbt repo self-contained (runnable without a live Frappe site) **and**
   drift-proof (the committed file is a pure function of the committed fixtures) — the standard
   pattern for committed generated code. **Implied work:** the regenerator needs a *build-from-
   fixtures* mode (today it reads a live site DB). Interim until CI exists: gitignore the two files.

3. **Empty `erp_sources` → allowed and valid; warn, don't block.** A fully-drained registry is a
   legitimate steady state (empty gold), made safe by the §3 empty-union guard. Add a **non-blocking
   warning** when deleting the last enabled connector ("this empties all data models"); `demo_data`
   is always re-addable. *Why:* maximally flexible + recoverable; the guard handles correctness, the
   warning handles human error. (Confirms AC#4.)

4. **dbt-template default → standardize every `var('erp_sources', …)` to `[]`.** Remove all hidden
   `['d365_fo']` template defaults. *Why:* one predictable behaviour whether the var is empty or
   absent; no lurking default to surprise a future reader. (Safe given the §3 guard.)

5. **Add-on packaging → DEFER, but define a tested "canonical contract" now.** Keep all adapters in
   core (gated by `erp_sources`) for now; do **not** split into per-ERP packages yet. Instead, write
   down and **schema-test the canonical staging contract** (the exact column set every
   `staging/<erp>` adapter must emit). *Why:* avoids premature multi-package overhead for today's 2
   ERPs while making a future split mechanical. When a real need appears (e.g. an out-of-tree /
   proprietary connector), split into **one dbt package per ERP** against that contract; the
   `erp_type` Select options then move into each add-on.

6. **Demo legal entities → a fixed small set, reused everywhere.** The `demo_data` connector declares
   **2–3 demo entities** (e.g. `DEMO-US`, `DEMO-DE`, `DEMO-GROUP`), and the *same* IDs are used in
   the seed CSVs' `entity_id` column and any demo crosswalk rows. *Why:* enough to demonstrate
   multi-entity consolidation without bloat; keeping the IDs identical everywhere makes
   `entities_loaded` / Connector Health counts and harmonization line up. The connector fixture is
   the canonical declaration of the list.

## Open Questions

None — all six design questions are resolved (see Resolved Decisions). Implementation may surface
mechanical details (e.g. the exact entry point for the regenerator's build-from-fixtures mode used by the
CI sync check); raise those on the implementing PR.

## Affected components (reference for the implementer)
- `konsol/dbt_config.py` — `regenerate_vars()` fallback (§2); `_regenerate_dimension_mappings_seed()` guard (§4).
- `konsol/pipeline/doctype/connector/connector.json` — `erp_type` options (§1).
- `konsol/install.py` — `after_migrate` ordering of seed regeneration vs fixture load (§4).
- `konsol/hooks.py` — fixtures already declared; add the missing JSON files (§1, §4).
- `konsol/fixtures/connector.json`, `konsol/fixtures/dimension_mapping.json` — new (§1, §4).
- `dbt_project/models/staging/demo_data/*.sql` — new adapter (§1).
- `dbt_project/models/staging/canonical/*.sql` (7) — empty-union guard (§3); `var('erp_sources', [])` (Decision #4).
- `dbt_project/seeds/` — demo transactional seeds wiring; `dimension_mappings.csv` becomes generated (§4).
- `konsol/dbt_config.py` — **new build-from-fixtures mode** for the CI sync check (Decision #2).
- CI config (e.g. `.github/workflows/`) — regenerate-from-fixtures drift check (Decision #2, AC#9) + canonical-contract schema test (Decision #5, AC#11).
- Connector doctype validation/UI — non-blocking warning on deleting the last enabled connector (Decision #3, AC#10).
- `dbt_project/models/staging/` — documented + schema-tested **canonical column contract** (Decision #5).
