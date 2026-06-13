# PRD: D365 Business Central Connector

**Status:** Not Started
**Date:** 2026-06-13
**Phase:** Phase 3 — Multi-ERP Support (PRD 32)
**Repos:** `konsolidat` (dbt/data stack + Airbyte source connector)

## Problem

- Konsolidat ships a single ERP connector — D365 F&O (`source_d365_fno`, OData v2 BI entities, `stg_d365_fo__*` adapter). The canonical staging interface (PR #10) exists precisely so additional ERPs can plug in, but no second ERP has been wired in yet, so `erp_sources: [d365_fo]` is the only value the stack has ever exercised.
- D365 Business Central is a **completely different product** from F&O (roadmap note, line 122): different API surface (REST v2.0 / OData v4 `api/v2.0` vs F&O `/data/` BI entities), different GL entity (`generalLedgerEntries` vs `GeneralJournalAccountEntryBiEntities`), and a different dimension model (BC `dimensionSetLines` keyed by company GUID, not F&O `DimensionAttributes`/`FinancialDimensionValues`).
- BC customers cannot be consolidated today. There is no `source_d365_bc` Airbyte source and no `stg_d365_bc__*` adapter, so BC GL never reaches `stg_gl_entries` / bronze / silver / gold.
- The canonical schema already reserves `d365_bc` as a valid `erp_source` value (`canonical-staging-schema.md` line 54) and `test_erp_source_valid.sql` will accept it — but nothing produces rows with it.

## Solution

Build a new Airbyte source connector `source_d365_bc` (BC REST/OData v4 client, mirroring the `source_d365_fno` CDK structure) plus a `stg_d365_bc__*` dbt adapter that maps BC API entities to the canonical staging schema, gated behind `erp_sources: [..., d365_bc]`.

## Scope

### 1. Airbyte source connector `source_d365_bc`

New package `source-d365-bc/source_d365_bc/` mirroring the F&O layout (`source.py`, `auth.py`, `streams.py`, `spec.yaml`, `schemas/`, `unit_tests/`).

**Auth** — reuse the F&O Azure AD v2.0 client-credentials pattern (`D365OAuth2Authenticator`). BC differs only in the token scope and base URL:

| Item | D365 F&O | D365 BC |
|------|----------|---------|
| Token URL | `login.microsoftonline.com/{tenant}/oauth2/v2.0/token` | same |
| Scope | `{env_url}/.default` | `https://api.businesscentral.dynamics.com/.default` |
| API base | `{env_url}/data/` | `https://api.businesscentral.dynamics.com/v2.0/{tenant}/{environment}/api/v2.0/` |
| Pagination | `$top`/`$skip` + `@odata.nextLink` | `@odata.nextLink` (BC v4 nextLink-only) |
| OData version | 4.0 headers | 4.0 |

**`spec.yaml` fields:** `tenant_id`, `client_id`, `client_secret` (all `airbyte_secret`), `bc_environment` (e.g. `production` / `sandbox`, replaces F&O `environment_url`), `page_size` (default 5000), optional `company_ids` (filter; default all companies — BC has no F&O `cross-company` flag, so iterate `companies` and slice GL per company GUID).

**Streams** (BC entity → stream name → cursor):

| BC entity (`api/v2.0`) | Stream name | Sync | Cursor |
|------------------------|-------------|------|--------|
| `companies` | `companies` | full refresh | — |
| `generalLedgerEntries` | `general_ledger_entries` | incremental | `postingDate` |
| `accounts` (chart of accounts) | `accounts` | full refresh | — |
| `dimensions` | `dimensions` | full refresh | — |
| `dimensionValues` | `dimension_values` | full refresh | — |
| `dimensionSetLines` | `dimension_set_lines` | incremental | `lastModifiedDateTime` |
| `currencies` | `currencies` | full refresh | — |
| `currencyExchangeRates` | `currency_exchange_rates` | incremental | `startingDate` |
| `generalLedgerSetup` / `accountingPeriods` | `accounting_periods` | full refresh | — |

GL entries and dimension set lines are sliced per company (BC scopes most entities under `companies({id})/...`). Reuse the F&O `should_retry`/`backoff_time` 429+5xx handling and the `odata_filter_literal` injection guard for cursor `$filter`.

### 2. dbt adapter `stg_d365_bc__*`

New `models/staging/d365_bc/` directory, one adapter model per canonical model it can populate, plus `_d365_bc__sources.yml` (source `d365_bc_raw`) and `_d365_bc__models.yml`.

| Adapter model | Canonical target | Source BC stream |
|---------------|------------------|------------------|
| `stg_d365_bc__gl_entries.sql` | `stg_gl_entries` | `general_ledger_entries` (+ `dimension_set_lines`) |
| `stg_d365_bc__accounts.sql` | `stg_accounts` | `accounts` |
| `stg_d365_bc__legal_entities.sql` | `stg_legal_entities` | `companies` |
| `stg_d365_bc__exchange_rates.sql` | `stg_exchange_rates` | `currency_exchange_rates` |
| `stg_d365_bc__fiscal_periods.sql` | `stg_fiscal_periods` | `accounting_periods` |
| `stg_d365_bc__trial_balance.sql` | `stg_trial_balance` | derived from `general_ledger_entries` (BC has no prebuilt TB snapshot entity) |

Every adapter emits `erp_source = 'd365_bc'` and the exact canonical column set (`canonical-staging-schema.md` §"Canonical Column Specifications"), casting all to `String`.

**BC → canonical column mapping (`stg_d365_bc__gl_entries`):**

| BC field | Canonical column |
|----------|------------------|
| `id` / `systemId` | `record_id` |
| `company.id` (GUID) or `companyName` | `entity_id` |
| `postingDate` | `posting_date` |
| `accountNumber` | `main_account` |
| `description` | `description` / `account_name` |
| `debitAmount` | `debit_amount` |
| `creditAmount` | `credit_amount` |
| `debitAmount - creditAmount` | `amount` (signed) |
| (`creditAmount > 0`) | `is_credit` ('1'/'0') |
| `documentNumber` | `journal_number` |
| `_airbyte_extracted_at` | `_loaded_at` |
| `_airbyte_raw_id` | `_raw_id` |

**BC dimension → canonical dimension mapping:** BC dimensions are user-defined (no fixed cost-center/department like F&O). Resolve via `dimension_set_lines` joined on the GL entry's `dimensionSetId`, then map BC dimension `code` to canonical slots by convention:

| BC dimension code (configurable) | Canonical column |
|----------------------------------|------------------|
| `COSTCENTER` / `KOST1` | `dim_cost_center` |
| `DEPARTMENT` | `dim_department` |
| `BUSINESSGROUP` / `AREA` | `dim_business_unit` |

The code→slot map lives in a dbt var (`bc_dimension_map`) so each tenant's BC dimension naming can be configured without model edits; unmapped dimensions fall through to empty string.

### 3. Wiring

- `dbt_project.yml`: add `d365_bc` to `erp_sources` (and `bc_dimension_map` var) to activate the BC arm of every canonical `UNION ALL`.
- Canonical models (`stg_gl_entries.sql` etc.) already `UNION ALL` adapters gated by `var('erp_sources')` — add the conditional `stg_d365_bc__*` branch following the F&O pattern. No bronze/silver/gold changes (they consume canonical only).
- Admin docs: add `docs/admin-guide/d365-bc-integration.md` covering the BC-specific Azure AD permission (`Dynamics 365 Business Central` API, `app_access` / `API.ReadWrite.All`) and the `api/v2.0` base URL.

## Out of Scope

- F&O connector or `stg_d365_fo__*` changes.
- SAP (S/4HANA, ECC, B1) and ERPNext connectors (separate PRDs 33–36).
- BC custom/extension APIs and Bound Actions; only the standard `api/v2.0` automation entities.
- BC webhooks / event-driven sync (incremental cursor pull only).
- Silver/gold/Cube.js/Excel changes — canonical interface insulates them.
- Auto-discovery of BC dimension codes; the `bc_dimension_map` var is configured manually per tenant.

## Acceptance Criteria

1. `source_d365_bc check` succeeds against a BC sandbox with valid client credentials and returns a generic (non-secret-leaking) error on bad creds, matching `auth_error_message` behaviour.
2. `source_d365_bc discover` returns exactly the 9 streams in Scope §1, each with a JSON schema file under `schemas/`.
3. `general_ledger_entries` and `currency_exchange_rates` advance their cursors (`postingDate`, `startingDate`) across incremental syncs; tampered cursor state cannot inject OData `$filter` (covered by a `source_d365_bc` security unit test mirroring `test_security_hardening.py`).
4. `dbt build` with `erp_sources: [d365_fo, d365_bc]` passes with zero regressions; F&O-only gold outputs are byte-identical to the `[d365_fo]` build.
5. `models/staging/d365_bc/` contains 6 adapter models; each produces the canonical column set for its target with `erp_source = 'd365_bc'`.
6. `test_erp_source_valid.sql` passes with `d365_bc` rows present, and `not_null` schema tests on canonical key columns (`record_id`, `entity_id`, `posting_date`, `main_account`, `amount`) pass for BC rows.
7. `stg_gl_entries` returns rows where `erp_source = 'd365_bc'`, sliced per BC company, with `dim_cost_center` populated from `dimension_set_lines` for entries whose dimension code is in `bc_dimension_map`.
8. `pytest source-d365-bc/unit_tests/` passes (auth, source, streams, security hardening).

## Open Questions

- Does the standard BC `api/v2.0` expose enough GL detail (dimensions on `generalLedgerEntries`) or must we fall back to the `g/L Entries` extension/standard API page for `dimensionSetId`? Verify against a live BC environment.
- Multi-environment tenants: one Airbyte source per BC `environment` (production/sandbox), or a single source iterating environments? Default to one source per environment for clarity.
- Should `stg_d365_bc__trial_balance` derive a TB by aggregating GL, or be omitted until a BC TB API page is confirmed (it would then carry no `d365_bc` rows, which is acceptable)?
