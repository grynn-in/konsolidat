# PRD: SAP Business One Connector

**Status:** Not Started
**Date:** 2026-06-13
**Phase:** Phase 3 — Multi-ERP Support (PRD 35)
**Repos:** `konsolidat` (dbt/data stack), `source-sap-b1` (new Airbyte source connector)

## Problem

- Konsolidat consolidates GL data across ERPs, but only D365 F&O is wired up (`stg_d365_fo__*` adapter, `erp_source = 'd365_fo'`). SAP Business One (B1) — common in SMB/mid-market subsidiaries that roll up into a larger group — has no extraction path or staging adapter.
- The canonical staging interface (`models/staging/canonical/stg_gl_entries.sql` and 6 siblings) already reserves `sap_b1` as a valid `erp_source` value, and every canonical model `UNION ALL`s `{{ ref('stg_' ~ erp ~ '__gl_entries') }}` over `var('erp_sources')`. The adapter side simply does not exist.
- B1 has no OData v4 surface like F&O. GL is exposed through the **Service Layer** REST API (OData-flavoured but distinct), with journal entry headers in `OJDT` (`JournalEntries`) and lines in `JDT1` (`JournalEntries/.../JournalEntryLines`). Authentication is a session-cookie login, not Azure AD OAuth2 — so the D365 OAuth authenticator cannot be reused as-is.

## Solution

Ship a B1 Airbyte HTTP source (`source-sap-b1`) that pulls Service Layer entities into a `sap_b1_raw` schema, plus a dbt adapter `models/staging/sap_b1/stg_sap_b1__*` whose 7 models emit the exact canonical column contract. Adding B1 to a deployment becomes: deploy the adapter, append `sap_b1` to `vars.erp_sources`, `dbt build`.

## Scope

### 1. Airbyte source connector (`source-sap-b1`)

Mirror the structure of `source-d365-fno/` (`source.py`, `streams.py`, `auth.py`, `spec.yaml`, `schemas/*.json`, `unit_tests/`). Base stream over Service Layer `b1s/v1`.

**Connector spec (`spec.yaml`):**

| Field | Type | Notes |
|-------|------|-------|
| `service_layer_url` | string | e.g. `https://b1srv:50000/b1s/v1` |
| `company_db` | string | B1 company database (`CompanyDB`) |
| `username` | string (secret) | Service Layer user |
| `password` | string (secret) | |
| `verify_ssl` | boolean | default `true`; B1 ships self-signed certs |
| `page_size` | integer | default 100 (Service Layer caps `$top`) |

**Auth (`SAPB1SessionAuthenticator`):** `POST {url}/Login` with `{CompanyDB, UserName, Password}`; capture the `B1SESSION` (and `ROUTEID`) cookie, re-login on `401`. `check_connection()` performs a login and returns a generic, non-sensitive failure message (follow `auth.py` conventions). Honour the session timeout (~30 min) with a buffer.

**Pagination:** Service Layer returns `@odata.nextLink` with skip tokens; follow it until absent (same `next_page_token` shape as `D365ODataStream`). Send `Prefer: odata.maxpagesize=<page_size>`.

**Streams (`name` → Service Layer entity):**

| Stream `name` | Entity | Cursor (incremental) | Canonical target |
|---------------|--------|----------------------|------------------|
| `journal_entries` | `JournalEntries` (OJDT + JDT1 lines) | `UpdateDate` | `stg_sap_b1__gl_entries`, `stg_sap_b1__gl_journal_entries` |
| `chart_of_accounts` | `ChartOfAccounts` | — | `stg_sap_b1__accounts` |
| `companies` | `CompanyService_GetCompanyInfo` / `BusinessPartners` (company info) | — | `stg_sap_b1__legal_entities` |
| `exchange_rates` | `SBOBobService_GetCurrencyRate` / `ORTT` | `RateDate` | `stg_sap_b1__exchange_rates` |
| `budget` | `Budget` / `BudgetScenarios` | — | `stg_sap_b1__budget_entries` |
| `financial_periods` | `FinancialPeriods` / `PostingPeriods` | — | `stg_sap_b1__fiscal_periods` |
| `cost_center_dimensions` | `ProfitCenters` / `Dimensions` | — | dimension lookup for `dim_*` |

GL lines: each `JournalEntries` record nests `JournalEntryLines`; the stream flattens lines, carrying header fields (`JdtNum`, `ReferenceDate`, `Memo`) onto each line so the GL adapter has one row per `JDT1` line.

### 2. dbt adapter (`models/staging/sap_b1/`)

One source def + 7 canonical-output models, matching the `d365_fo` adapter layout. `erp_source` literal is `'sap_b1'` everywhere.

| Model | Source entity | Notes |
|-------|---------------|-------|
| `_sap_b1__sources.yml` | declares `sap_b1_raw` source | |
| `stg_sap_b1__gl_entries.sql` | `journal_entries` (flattened lines) | canonical `stg_gl_entries` contract |
| `stg_sap_b1__gl_journal_entries.sql` | `journal_entries` (header) | internal helper, header per `JdtNum` |
| `stg_sap_b1__accounts.sql` | `chart_of_accounts` | |
| `stg_sap_b1__legal_entities.sql` | `companies` | one entity per `company_db` |
| `stg_sap_b1__exchange_rates.sql` | `exchange_rates` | |
| `stg_sap_b1__budget_entries.sql` | `budget` | |
| `stg_sap_b1__fiscal_periods.sql` | `financial_periods` | |

**GL line → canonical mapping (`stg_sap_b1__gl_entries`):**

| Canonical column | B1 source (JDT1/OJDT) |
|------------------|----------------------|
| `erp_source` | literal `'sap_b1'` |
| `record_id` | `JdtNum` ~ `Line_ID` (`JdtNum '-' Line_ID`) |
| `entity_id` | `company_db` (B1 = one company DB per legal entity) |
| `posting_date` | `RefDate` (`OJDT.RefDate`), truncated to `YYYY-MM-DD` |
| `fiscal_year` | derived from `RefDate` / `FinancialPeriod` |
| `fiscal_period` | `FinancialPeriod` |
| `main_account` | `AccountCode` (`JDT1.Account`) |
| `account_name` | `''` (join `stg_sap_b1__accounts` downstream) |
| `amount` | `Debit - Credit` (signed; positive = debit) |
| `transaction_currency_amount` | `FCDebit - FCCredit` |
| `transaction_currency` | `FCCurrency` |
| `description` | `LineMemo`, else `OJDT.Memo` |
| `journal_number` | `JdtNum` |
| `posting_type` | `TransType` |
| `ledger_account` | `AccountCode` |
| `is_credit` | `1` if `Credit > 0` else `0` |
| `dim_cost_center` | `ProfitCenter` / `CostingCode` |
| `dim_department` | `CostingCode2` (B1 dimension 2) |
| `dim_business_unit` | `CostingCode3` |
| `_loaded_at` | `_airbyte_extracted_at` |
| `_raw_id` | `_airbyte_raw_id` |

Select only the canonical column set in the union-facing model (extra adapter columns like `FCDebit` stay internal), matching the comment contract in `stg_gl_entries.sql`.

### 3. Wiring

- Add `sap_b1` to `vars.erp_sources` in `dbt_project.yml` (per-deployment opt-in; default stays `['d365_fo']`).
- No changes to canonical, bronze, silver, gold, Cube.js, or `konsol` API — the canonical contract is the seam. Connector Registry integration (Frappe) is PRD 37, out of scope here.

## Out of Scope

- Connector Registry doctype / Frappe UI for B1 credentials (PRD 37).
- Sub-ledger facts (A/P, A/R, Fixed Assets) — only GL, accounts, entities, FX, budget, periods.
- B1 DI-API / direct HANA SQL extraction — Service Layer REST only.
- Dimension Harmonization across ERPs (separate roadmap task) — B1 dimensions land in `dim_cost_center/department/business_unit` as-is.
- Multi-company-DB consolidation inside one B1 server beyond mapping each DB to one `entity_id`.
- Incremental CDC tuning / ClickHouse sharding (Scale Architecture task).

## Acceptance Criteria

1. `source-sap-b1` `check_connection()` returns `(True, None)` against a live Service Layer with valid creds, and `(False, <generic msg>)` on bad creds without leaking the response body (pytest mirrors `unit_tests/test_security_hardening.py`).
2. `journal_entries` stream emits one record per `JDT1` line with header fields attached; `chart_of_accounts`, `exchange_rates`, `budget`, `financial_periods`, `companies` each sync to `sap_b1_raw`.
3. Pagination follows `@odata.nextLink` to completion; session re-login occurs transparently on `401`.
4. `models/staging/sap_b1/` contains exactly 7 SQL models + sources yml; each GL/TB/accounts/entities/FX/budget/periods model outputs the canonical column set with `erp_source = 'sap_b1'`.
5. With `erp_sources: [d365_fo, sap_b1]`, `dbt build` passes all existing canonical tests (`test_erp_source_valid.sql` accepts `sap_b1`; `not_null` on key columns) plus zero regressions on D365 outputs.
6. `select distinct erp_source from stg_gl_entries` returns both `d365_fo` and `sap_b1`; B1 GL rows flow through bronze → gold unchanged and balance (sum of `amount` per journal = 0 for balanced JEs).
7. With `erp_sources: [d365_fo]` (default), no B1 models are referenced and `dbt build` output is byte-identical to pre-B1.

## Open Questions

- B1 budget exposure varies by version (SAP HANA vs SQL Server; Service Layer `Budget` entity availability) — confirm the entity/path on the target B1 release, else fall back to leaving `stg_sap_b1__budget_entries` empty-but-conforming.
- Fiscal year/period derivation: use B1 `FinancialPeriods` directly, or derive from `RefDate` against the posting-period calendar? Prefer the explicit `FinancialPeriod` field on `OJDT` when present.
- `entity_id` granularity when a customer runs many B1 company DBs — one connector instance per DB, or one instance enumerating DBs? Default: one instance per DB (one `entity_id`).
- Service Layer rate limits / max session count under parallel per-entity syncs — may need a concurrency cap in `streams()`.
