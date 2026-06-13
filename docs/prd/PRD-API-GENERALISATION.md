# PRD: API Generalisation (generic dimensions/measures/facts)

**Status:** Not Started
**Date:** 2026-06-13
**Phase:** Phase 2.4 — Dynamic Schema (API)
**Repos:** `konsol` (Frappe app — `konsol/api.py`, EPM doctypes), `konsolidat` (docs/api-reference, Excel VBA `=EPM()` contract)

## Problem

The dbt layer (Phase 2.1/2.2/2.5) and the Frappe registries (`Dimension`, `Measure`, `Fact Table` doctypes under `konsol/epm/doctype/`) are already registry-driven. The read API in `konsol/api.py` is the last hardcoded link and is only partially generalised:

- `epm_value()` / `epm_batch()` still expose **named** `cost_center` and `department` params as the first-class dimension contract. Other dimensions are only reachable through undocumented `dim_*` kwargs, and the `dimensions` dict from the roadmap example (`dimensions={"cost_center": "CC001", "project": "P01"}`) is **not accepted** by either endpoint.
- There is **no `fact` parameter**. Table selection is driven entirely by `scenario` (`_get_fact_by_scenario` looks up `Fact Table.scenario_key`), so the universal GL fact and statistical/sub-ledger facts (Phase 2.3) cannot be addressed by name — a caller must know the magic scenario key that happens to map to the right table.
- Measure validation (`_check_measure`) reads the per-fact `measures` JSON, but the roadmap explicitly requires validation against the **active Measure registry** with the old hardcoded `ALLOWED_MEASURES` concept fully retired. There is no enforcement of `Measure.status == "Published"`.
- The published contract (`docs/api-reference/api-epm-value.md`, `api-epm-batch.md`, `api-overview.md`) documents `cost_center`/`department` and a fixed 3-scenario→table map, contradicting the registry-driven reality and the roadmap target signature.

## Solution

Make `epm_value`/`epm_batch` registry-driven end to end: accept a generic `dimensions` dict and a new `fact` param (default `GL`), validate `measure` against the active `Measure` registry and the resolved fact's allowed dimensions/measures, keep the old `cost_center`/`department`/`scenario` named params working via internal mapping, and update the Cube parity docs and Excel `=EPM()` contract to match.

## Scope

### 1. Request contract (both endpoints)

| Param | Type | Required | Default | Notes |
|---|---|---|---|---|
| `entity` | string | yes | — | unchanged (`data_area_id`) |
| `year` | int | yes | — | unchanged |
| `period` | string/int | yes | — | unchanged (`1`–`12`, `Q1`–`Q4`, `H1`, `H2`, `FY`) |
| `account` | string | yes | — | unchanged (`main_account`) |
| `measure` | string | no | `period_net_amount` | validated against active `Measure` registry **and** resolved fact's `measures` |
| `fact` | string | no | `GL` | **new** — resolves to a `Fact Table` by `fact_name`; selects `clickhouse_table` |
| `dimensions` | dict | no | `{}` | **new** — `{canonical_dimension_name: value}`, e.g. `{"cost_center": "CC001", "project": "P01"}` |
| `scenario` | string | no | `actuals` | **legacy** — kept; still resolves via `scenario_key` when `fact` not given |
| `cost_center` | string | no | `""` | **legacy** — mapped into `dimensions["cost_center"]` |
| `department` | string | no | `""` | **legacy** — mapped into `dimensions["department"]` |
| `scenario_id` | string | no | `""` | unchanged; applies only when fact `has_scenario_id` |

Excel `=EPM()` target: `=EPM("USMF", 2024, "Q1", "401100", dimensions={"cost_center":"CC001","project":"P01"})`.

### 2. Fact resolution

Add `_get_fact(fact=None, scenario=None)` in `api.py`:

1. If `fact` is given → load `Fact Table` by `fact_name` (case-insensitive); error `Invalid fact '{x}'. Allowed: {published fact_names}` if missing.
2. Else fall back to current `_get_fact_by_scenario(scenario)` for backward compatibility.
3. Default `fact="GL"` resolves to the pre-seeded universal GL `Fact Table` (Phase 2.3 core fact, `clickhouse_table = epm_gold.gold_trial_balance`).

`_get_fact_by_scenario` stays as the legacy path; both return the same dict shape (`clickhouse_table`, `measures`, `dimensions`, `has_scenario_id`, reroute fields).

### 3. Dimension handling

- Accept `dimensions` as a dict on `epm_value` (query-string JSON or repeated `dimensions[<name>]=` style) and on each `epm_batch` item.
- Build the canonical dimensions dict by merging, in precedence order: legacy `cost_center`/`department` named params → explicit `dimensions` dict (explicit wins).
- Drop the `dim_` prefix requirement from the public contract: keys are **canonical dimension names** (matching `Dimension.dimension_name`). Internally the query builder maps each name to its ClickHouse column.
- Validate every supplied dimension name against the resolved fact's `dimensions` JSON (the fact's allowed dimensions); unknown name → `Invalid dimension '{x}' for fact '{f}'. Allowed: {...}`.
- Keep the existing `_SAFE_IDENTIFIER` regex guard before any SQL interpolation.

### 4. Measure validation against active registry

- Replace per-fact-only checking: `_check_measure(measure, fact)` validates the measure is (a) a `Measure` with `status == "Published"` AND (b) present in the resolved fact's `measures` JSON.
- Error: `Invalid measure '{m}' for fact '{f}'. Allowed: {sorted intersection of published measures and fact measures}`.
- Remove any remaining reference to a hardcoded `ALLOWED_MEASURES` dict (none should survive; assert by test).

### 5. Query builder

`_batch_query_clickhouse` already groups by `(scenario, measure, periods, frozenset(dim_names), scenario_id)`. Changes:

- Group key gains `fact` (replacing `scenario` as the table-determining element); the table is read from the resolved fact, not from scenario.
- Dimension column names come from the `Dimension` registry mapping (canonical name → ClickHouse column), not assumed equal to the param key.
- No change to the parameterized `IN`-tuple batching or reroute logic.

### 6. Docs & Excel contract

| Artifact | Change |
|---|---|
| `docs/api-reference/api-epm-value.md` | document `fact` + `dimensions` dict; mark `cost_center`/`department`/`scenario` legacy; replace "[see allowed measures]" with "active Measure registry" |
| `docs/api-reference/api-epm-batch.md` | add `fact`/`dimensions` to request object; update grouping note to include `fact` |
| `docs/api-reference/api-overview.md` | replace fixed Scenario→Table map with "Fact registry → ClickHouse table"; update grouping/validation tables |
| `docs/reference/semantic-layer.md` | note parity rule now keys on fact + canonical dimension names |
| Excel VBA `=EPM()` | emit `dimensions` dict in batch payload; keep positional `cost_center`/`department` accepted for old sheets |

## Out of Scope

- ClickHouse DDL auto-generation on `Dimension`/`Measure`/`Fact Table` save (Phase 2.1/2.2/2.3 open items).
- Budget write-back endpoints (`budget_save*`) — they already read `Dimension` with `in_budget`/`status` filters; no contract change here.
- Cube.js schema generation (`scripts/generate_cube_schemas.py`) — covered by the source-of-truth rule, not this PRD.
- New statistical/sub-ledger fact **content** (Headcount, Area, AR/AP) — this PRD only makes the API able to address any fact by name.
- Multi-ERP source adapters (Phase 3).

## Acceptance Criteria

1. `epm_value(entity="USMF", year=2024, period="Q1", account="401100", dimensions={"cost_center":"CC001","project":"P01"})` returns `{"value": <number>}` and filters on both dimensions.
2. `epm_value(...)` with no `fact` and no `scenario` queries the `GL` fact (`gold_trial_balance`) and returns the same value as the legacy `scenario="actuals"` call for identical coordinates.
3. Calling with legacy `cost_center="CC001"` (no `dimensions` dict) returns the identical value to passing `dimensions={"cost_center":"CC001"}` — backward compatibility test passes.
4. `fact="budget"` (or its registry `fact_name`) selects the budget `Fact Table`'s `clickhouse_table`; an unknown `fact` returns `Invalid fact '...'. Allowed: ...`.
5. A `measure` that exists in a fact's `measures` but whose `Measure.status != "Published"` is **rejected**; a published measure not in the fact's `measures` is **rejected**; the error lists only the valid intersection.
6. `epm_batch` accepts per-item `fact` and `dimensions`; grouping produces one SQL query per `(fact, measure, period_tuple, dim-name set, scenario_id)` group (verified by counting ClickHouse calls in a 350-cell mixed-fact batch).
7. An unknown dimension name in `dimensions` yields a per-item inline error in `epm_batch` and a `ValidationError` in `epm_value`, with no SQL executed for that item.
8. `grep -n ALLOWED_MEASURES konsol/api.py` returns no matches; pytest asserts the symbol is absent.
9. Docs (`api-epm-value.md`, `api-epm-batch.md`, `api-overview.md`) document `fact` and `dimensions`, and no longer present `cost_center`/`department` as the primary dimension mechanism.
10. Existing pytest suite for `epm_value`/`epm_batch` passes unchanged for all legacy-param call shapes (no regression).

## Open Questions

- Query-string encoding of `dimensions` for the GET `epm_value` (JSON-encoded string vs `dimensions[name]=value` bracket syntax) — pick one and document; batch (POST JSON) is unambiguous.
- Canonical name vs ClickHouse column mapping: is `Dimension.source_column` the warehouse column, or is there a separate gold-layer column name? Confirm the registry field the query builder should map to.
- Should `fact` and `scenario` both being supplied be an error, or should `fact` silently win? (Proposed: `fact` wins, warn.)
- Case sensitivity / aliasing for `fact_name` lookup (e.g. `GL` vs `gl` vs `gold_trial_balance`).
