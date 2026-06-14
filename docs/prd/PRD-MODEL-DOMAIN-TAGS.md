# PRD: Manage Gold Model → Build Domain Assignment in Frappe

**Status:** Proposed
**Date:** 2026-06-14
**Repos:** `konsol` (doctype + generator), `konsolidat` (`dbt_project.yml` consumer)
**Related:** `PRD-BUILD-GOVERNANCE.md`

## Problem

Build Governance runs **scoped** dbt builds: each governed build selects a domain and
runs `dbt build --select tag:domain:<domain>` (see `konsol.tasks.SCOPE_SELECTOR`). The
mapping of **which gold model belongs to which domain** lives as hand-maintained tags in
`dbt_project.yml`:

```yaml
models:
  open_epm:
    gold:
      gold_trial_balance:
        +tags: ['gold', 'domain:actuals']
      gold_variance_analysis:
        +tags: ['gold', 'domain:scenarios']
      # ...31 gold models total
```

This is the last significant pipeline config **not** managed in Frappe (dimensions,
measures, fiscal periods, and erp_sources/connectors already are). Consequences:

- **Blast radius on a typo.** A wrong or missing `domain:` tag silently changes which
  models a governed build rebuilds — e.g. an `actuals` model mistagged `scenarios` is
  skipped by an actuals build, so its ClickHouse table goes stale with no error.
- **No UI / audit.** Reassigning a model's domain means hand-editing YAML on the dbt host;
  there's no Frappe record, permission gate, or change history.
- **Regeneration churn.** `regenerate_vars()` already rewrites `dbt_project.yml`; the
  model tags sitting in the same file are fragile alongside generated content.

## Goal

Make Frappe the **source of truth** for the gold-model → domain assignment, mirroring how
Dimension/Measure/Connector already drive `dbt_project.yml`. Editing a model's domain
becomes a governed doctype change that regenerates the tags.

### Non-goals

- Managing the **domain set itself** (staging/actuals/scenarios/consolidation). Those stay
  in `konsol.tasks.SCOPE_SELECTOR` for now; making them a doctype is a possible follow-up.
- Managing materialization / schema / layer config in the `models:` block — only the gold
  models' `domain:` tag is generated; everything else is preserved.
- Changing how a governed build *selects* by tag (unchanged: `tag:domain:<x>`).

## Design

### Doctype — `Gold Model` (Pipeline module)
| Field | Type | Notes |
|---|---|---|
| `model_name` | Data (unique, autoname) | dbt gold model, e.g. `gold_trial_balance` |
| `build_domain` | Select | `staging` / `actuals` / `scenarios` / `consolidation` (in sync with `SCOPE_SELECTOR`) |
| `description` | Small Text | optional |

Permissions: System Manager + EPM Admin. Seeded via **fixtures** with the current 31 gold
models and their domains; added to `hooks.fixtures`.

### Generator — `konsol.dbt_config`
- `_apply_model_domains(project, mapping)` — **pure** (no Frappe): rewrites
  `models.open_epm.gold.<model>.+tags` to `['gold', 'domain:<domain>']`. Preserves the gold
  layer config (`+schema`, `+materialized`, `+tags`) and any models not in the mapping;
  unit-testable.
- `_build_model_domain_mapping()` — reads `{model_name: build_domain}` from `Gold Model`.
- `regenerate_model_domains()` — loads `dbt_project.yml`, applies the mapping, writes back.
  **Empty doctype ⇒ YAML untouched** (nothing to manage yet).
- `Gold Model.on_update` / `on_trash` → `regenerate_model_domains()`.

### Flow
```
EPM Admin edits Gold Model.build_domain
   → on_update → regenerate_model_domains()
      → rewrite gold +tags in dbt_project.yml
         → next governed build selects tag:domain:<x> correctly
```

## Deliverables (konsol)
- `konsol/pipeline/doctype/gold_model/` (json, py, __init__)
- `konsol/fixtures/gold_model.json` (31 records, generated from the current YAML)
- `konsol/dbt_config.py` (+`_apply_model_domains`, `_build_model_domain_mapping`, `regenerate_model_domains`)
- `konsol/hooks.py` (fixtures += "Gold Model")
- `konsol/tests/test_dbt_config.py` (pure-function + source-inspection tests)

## Risks / open items
- **Coupling to Build Governance.** The `build_domain` options must stay in lockstep with
  `SCOPE_SELECTOR`. A future "Build Domain" doctype would make that single-source; until
  then both lists are hardcoded to the same four values, validated in the controller.
- **Comment loss.** `yaml.dump` (as with `regenerate_vars`) cannot preserve comments, so
  regenerating reformats the `models:` block. Acceptable for a generated file; noted.
- **New models.** A gold model added to dbt but not registered as a `Gold Model` doc keeps
  whatever tag is in the YAML (the generator only touches mapped models). A CI check that
  every `models.open_epm.gold.*` has a matching `Gold Model` doc would close this gap
  (follow-up).
- **Not runtime-verified** — needs a live bench to confirm `on_update` regeneration + a
  governed build picking up the rewritten tags.
