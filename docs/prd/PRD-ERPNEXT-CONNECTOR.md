# PRD: ERPNext Connector

**Status:** Implemented (konsolidat #37)
**Date:** 2026-06-13
**Phase:** Phase 3 — Multi-ERP Support (PRD 36)
**Repos:** `konsolidat` (dbt adapter + Airbyte source), `konsol` (Frappe API client, optional direct-extract path)

## Problem

- The canonical staging interface (`models/staging/canonical/`, 7 models) and the D365 F&O adapter (`stg_d365_fo__*`) are done, but the only registered ERP in `var('erp_sources')` is `d365_fo`. Customers running ERPNext (itself a Frappe app, like `konsol`) cannot land their GL into the consolidation pipeline.
- The canonical schema reserves `erp_source = 'erpnext'` (see `canonical-staging-schema.md`) but no adapter produces it. Bronze/silver/gold are already ERP-agnostic, so the entire gap is between raw ERPNext data and the canonical layer.
- ERPNext's financial data lives in well-known doctypes — `GL Entry`, `Account`, `Company`, `Currency Exchange`, `Budget`, `Fiscal Year` — exposed over the standard Frappe REST API (`/api/resource/<DocType>`, `/api/method/<dotted.path>`). Unlike D365 (OData, OAuth2 service principal), ERPNext authenticates with a simple `token <api_key>:<api_secret>` header. No connector exists for this contract.
- ERPNext's analytical dimensions are `Cost Center` and `Project` (plus optional custom Accounting Dimensions) carried as columns on `GL Entry`, not a JSON dimension blob like D365's `LedgerDimensionValuesJson`. The canonical `dim_*` columns must be mapped from these flat fields.

## Solution

Add an ERPNext adapter that lands six `GL Entry`-family doctypes via the Frappe REST API (Airbyte HTTP source or a direct `konsol` extractor), then transforms them through `stg_erpnext__*` dbt models into the existing canonical 7-model interface. Register `erpnext` in `erp_sources`; no changes to canonical/bronze/silver/gold.

## Scope

### 1. Extraction — Frappe REST source

ERPNext exposes every doctype at `GET /api/resource/<DocType>?fields=[...]&filters=[...]&limit_page_length=N&limit_start=M`, auth header `Authorization: token <api_key>:<api_secret>`. Page with `limit_start`/`limit_page_length`; incremental via filter on `modified`. Two supported landing paths (pick one per deployment):

- **Airbyte ERPNext** — community HTTP/ERPNext source, one stream per doctype below, cursor `modified`. Mirrors the D365 source layout (`source-d365-fno/`): `spec.yaml` (host_url, api_key, api_secret, page_size), `streams.py` (one `ERPNextStream` per doctype), JSON schemas per stream.
- **Direct Frappe extract** — `konsol` task that calls ERPNext REST and writes the same raw tables into `epm_raw`. The Frappe client pattern already exists in `konsol` (`api.py` uses `requests` for ClickHouse; same `requests` + token-header approach applies). Useful when ERPNext and `konsol` share an operator and Airbyte is undesired.

| Stream (raw table) | ERPNext DocType | Cursor | Key fields pulled |
|---|---|---|---|
| `gl_entry` | `GL Entry` | `modified` | name, company, posting_date, fiscal_year, account, debit, credit, against, voucher_no, cost_center, project, is_cancelled |
| `account` | `Account` | `modified` | name, account_name, root_type, account_type, company, disabled |
| `company` | `Company` | `modified` | name, default_currency, country |
| `currency_exchange` | `Currency Exchange` | `modified` | from_currency, to_currency, date, exchange_rate |
| `budget` + `Budget Account` (child) | `Budget` | `modified` | company, fiscal_year, cost_center, project, accounts (child: account, budget_amount) |
| `fiscal_year` | `Fiscal Year` | `modified` | name, year_start_date, year_end_date |

### 2. dbt adapter — `models/staging/erpnext/`

Mirror the D365 file structure. Each model emits `'erpnext' as erp_source` and the exact canonical column set (verified against `canonical/*.sql`):

| Adapter model | Canonical target | Source raw table(s) | Notes |
|---|---|---|---|
| `stg_erpnext__gl_entries.sql` | `stg_gl_entries` | `gl_entry` | `debit - credit` → `amount`; `is_credit` from sign; map `cost_center`→`dim_cost_center`, `project`→`dim_business_unit` (or new dim), `''`→`dim_department`; filter `is_cancelled = 0` |
| `stg_erpnext__accounts.sql` | `stg_accounts` | `account` | `root_type`→`account_type`, `account_type`→`account_category`, `disabled`→`is_suspended` |
| `stg_erpnext__legal_entities.sql` | `stg_legal_entities` | `company` | `name`→`entity_id`, `default_currency`→`accounting_currency`, `country`→`country_region` |
| `stg_erpnext__exchange_rates.sql` | `stg_exchange_rates` | `currency_exchange` | `date`→`valid_from`; `valid_to`/`rate_type` empty/default |
| `stg_erpnext__budget_entries.sql` | `stg_budget_entries` | `budget` + child | flatten `Budget Account`; `budget_amount`→`amount`; `cost_center`→`dim_cost_center` |
| `stg_erpnext__fiscal_periods.sql` | `stg_fiscal_periods` | `fiscal_year` | `name`→`fiscal_year`, `year_start_date`→`start_date`, `year_end_date`→`end_date` |
| `stg_erpnext__trial_balance.sql` | `stg_trial_balance` | (derived from `gl_entry`) | ERPNext has no TB snapshot doctype; aggregate GL per account/year, or emit empty and let silver derive |

Plus `_erpnext__sources.yml` (source `erpnext_raw`, database `epm_raw`, `loaded_at_field: _airbyte_extracted_at`) and `_erpnext__models.yml` (model docs + schema tests).

### 3. Dimension mapping — Cost Center / Project

ERPNext carries `cost_center` and `project` as flat columns on `GL Entry`. Map per the source-layer abstraction (`dim_select_from_source()`, Phase 2.5): canonical `dim_cost_center` ← `cost_center`, and `project` to a `dim_project` dimension (register in the Frappe `Dimension` doctype with `source_column = project`) or fold into `dim_business_unit` if no project dimension is configured. `dim_department` is empty for ERPNext unless a custom Accounting Dimension exists.

### 4. Registration

- Add `erpnext` to `vars.erp_sources` in `dbt_project.yml`. Canonical models then UNION the new adapter automatically (no canonical edits).
- Connector config (host_url, api_key, api_secret) registered in the future Connector Registry (Phase 3, PRD-CONNECTOR-REGISTRY); until then via Airbyte source config or `konsol` site config.

## Out of Scope

- Connector Registry doctype and per-connector health dashboard (separate Phase 3 PRD).
- Custom ERPNext Accounting Dimensions beyond Cost Center / Project (handled by Dimension Harmonization PRD).
- Incremental CDC tuning / ClickHouse sharding (Scale Architecture PRD).
- Sub-ledger facts (AP/AR/Fixed Assets) — only GL-family doctypes here.
- Any change to canonical, bronze, silver, gold, or consolidation logic.

## Acceptance Criteria

1. `models/staging/erpnext/` contains 7 `stg_erpnext__*` models, each selecting exactly the canonical column set of its target (`dbt compile` succeeds; column lists match `canonical/*.sql`).
2. With `erp_sources: [d365_fo, erpnext]`, `stg_gl_entries` returns the UNION ALL of both adapters and every row has `erp_source in ('d365_fo','erpnext')` — `test_erp_source_valid.sql` passes.
3. Every `stg_erpnext__gl_entries` row has non-null `erp_source`, `record_id`, `entity_id`, `posting_date`, `main_account` (not_null schema tests pass).
4. `dbt build` passes the full existing test suite (144 tests) with zero regressions; gold outputs for `d365_fo`-only deployments are byte-identical (the new adapter is inert unless `erpnext` is in `erp_sources`).
5. Extraction against a live/test ERPNext returns paged results with `Authorization: token <key>:<secret>`, honours `limit_start`/`limit_page_length`, and supports incremental sync on `modified`; `check_connection` succeeds with valid credentials and fails cleanly with invalid ones.
6. `cost_center` and `project` from `GL Entry` surface as `dim_cost_center` and the configured project/business-unit dimension in a consolidated `gold_trial_balance` query filtered to an ERPNext entity.

## Open Questions

- Trial balance: derive `stg_erpnext__trial_balance` by aggregating `GL Entry`, or emit empty and rely on silver to compute balances from GL? D365 has a native snapshot entity; ERPNext does not.
- Default landing path for shipped product — Airbyte ERPNext source vs. direct `konsol` Frappe extractor (the latter reuses the in-app Frappe client and avoids an extra service).
- `project` → dedicated `dim_project` dimension vs. mapping into existing `dim_business_unit`; depends on whether Dimension Harmonization standardises a project dimension across ERPs.
- Multi-company ERPNext: one connection per ERPNext site (multiple `Company` records in one site) vs. one connection per company — affects `entity_id` derivation and credential scoping.
