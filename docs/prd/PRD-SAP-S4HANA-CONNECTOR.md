# PRD: SAP S/4HANA Connector

**Status:** Not Started
**Date:** 2026-06-13
**Phase:** Phase 3 — Multi-ERP Support (PRD 33)
**Repos:** `konsolidat` (dbt/data stack + Airbyte source connector)

## Problem

- The canonical staging interface (`models/staging/canonical/stg_*`) and the D365 F&O adapter (`stg_d365_fo__*`) are complete, but `var('erp_sources')` lists only `d365_fo`. No SAP customer can be onboarded.
- SAP S/4HANA exposes GL data via OData v4 CDS views (`I_JournalEntry`, `I_GLAccountLineItem`), an entirely different API shape, entity model, and dimension system than D365 F&O OData v2 — none of the existing adapter logic (`LedgerDimensionValuesJson` parsing, `cross-company=true`, `$skip` pagination) applies.
- SAP's account-assignment dimensions are **cost center** (`CostCenter`), **profit center** (`ProfitCenter`), and **segment** (`Segment`), which do not line up 1:1 with the canonical `dim_cost_center` / `dim_department` / `dim_business_unit` slots used by the D365 adapter.
- There is no Airbyte source that emits the SAP CDS entities into a `sap_raw` bronze schema for dbt to consume.

## Solution

Build a Python Airbyte source connector (`source-sap-s4hana/`, mirroring `source-d365-fno/`) that extracts SAP CDS OData v4 entities, and a dbt adapter (`models/staging/sap_s4/stg_sap_s4__*`) that maps them onto the existing canonical staging schema. Register `sap_s4` in `var('erp_sources')` so the canonical models UNION the new adapter with zero changes to bronze/silver/gold.

## Scope

### 1. Airbyte source connector — `source-sap-s4hana/`

Clone the structure of `source-d365-fno/` (`source.py`, `streams.py`, `auth.py`, `spec.yaml`, `schemas/*.json`, `unit_tests/`). OData v4, `OData-Version: 4.0` header (D365 base already sends this), `$top`/`$skip` pagination with `@odata.nextLink` fallback (reuse the `D365ODataStream` pagination logic), `sap-client` query param instead of `cross-company`.

**Streams** (`name` → CDS entity, `url_base` = `{host}/sap/opu/odata4/sap/<service>/srvd_a2x/sap/`):

| Stream `name` | CDS Entity (OData v4) | Canonical adapter consumer |
|---|---|---|
| `journal_entries` | `I_JournalEntry` | header for `stg_sap_s4__gl_entries` |
| `gl_account_line_items` | `I_GLAccountLineItem` | lines for `stg_sap_s4__gl_entries` / `trial_balance` |
| `gl_accounts` | `I_GLAccountInChartOfAccounts` | `stg_sap_s4__accounts` |
| `company_codes` | `I_CompanyCode` | `stg_sap_s4__legal_entities` |
| `exchange_rates` | `I_ExchangeRate` | `stg_sap_s4__exchange_rates` |
| `fiscal_periods` | `I_FiscalYearVariantPeriod` | `stg_sap_s4__fiscal_periods` |
| `cost_centers` | `I_CostCenter` | dimension master (optional) |
| `profit_centers` | `I_ProfitCenter` | dimension master (optional) |

`gl_account_line_items` is the incremental stream — cursor field `LastChangeDate` (or `JournalEntryCreationDate`), filtered via OData v4 `$filter` using the existing `odata_filter_literal()` injection-safe helper.

### 2. Connector spec — `spec.yaml`

| Property | Type | Notes |
|---|---|---|
| `host` | string (secret) | e.g. `https://my-s4.s4hana.ondemand.com` |
| `auth_type` | enum | `oauth2_client_credentials` (BTP/IAS) or `basic` (technical user) |
| `client_id` / `client_secret` | string (secret) | OAuth2 client credentials path |
| `token_url` | string | OAuth2 token endpoint (IAS / XSUAA) |
| `username` / `password` | string (secret) | basic-auth path |
| `sap_client` | string | SAP client (mandant), e.g. `100` → `sap-client` param |
| `service_path` | string | OData v4 service root, default per CDS service binding |
| `page_size` | integer | default 5000, min 100, max 10000 |

`auth.py` provides two authenticators behind a common `get_auth_header()` interface: `SAPOAuth2Authenticator` (client-credentials, token caching + 60s buffer, generic non-sensitive error messages — mirror `D365OAuth2Authenticator`) and `SAPBasicAuthenticator`.

### 3. dbt adapter — `models/staging/sap_s4/`

Produce one model per canonical interface, each emitting `'sap_s4' as erp_source` and the exact canonical column set. Files: `_sap_s4__sources.yml` (defines `sap_raw` source), `_sap_s4__models.yml`, and `stg_sap_s4__{gl_entries,trial_balance,accounts,legal_entities,exchange_rates,budget_entries,fiscal_periods}.sql`.

**`stg_sap_s4__gl_entries`** column mapping (`I_GLAccountLineItem` joined to `I_JournalEntry` on `CompanyCode + FiscalYear + AccountingDocument`):

| SAP CDS field | Canonical column |
|---|---|
| `AccountingDocumentItem` (+ doc key) | `record_id` |
| `CompanyCode` | `entity_id` |
| `PostingDate` | `posting_date` |
| `FiscalYear` | `fiscal_year` |
| `FiscalPeriod` | `fiscal_period` |
| `GLAccount` | `main_account` |
| `AmountInCompanyCodeCurrency` | `amount` |
| `AmountInTransactionCurrency` | `transaction_currency_amount` |
| `TransactionCurrency` | `transaction_currency` |
| `DocumentItemText` | `description` |
| `AccountingDocument` | `journal_number` |
| `DebitCreditCode` (`H` = credit) | `is_credit` (`1` if `H`) |
| `CostCenter` | `dim_cost_center` |
| `ProfitCenter` | `dim_business_unit` |
| `Segment` | `dim_department` |
| `_airbyte_extracted_at` | `_loaded_at` |
| `_airbyte_raw_id` | `_raw_id` |

SAP `DebitCreditCode` is `S` (Soll/debit) or `H` (Haben/credit); amounts are signed in CDS, so set `is_credit = 1` when `DebitCreditCode = 'H'` and pass the absolute `amount` through (bronze/silver split debit/credit on `is_credit`, identical to D365). `ledger_account` and `posting_type` map from `GLAccountLineItem` `Ledger` / `FinancialAccountType`.

### 4. Dimension mapping (SAP → canonical)

| SAP dimension | Canonical slot | Rationale |
|---|---|---|
| `CostCenter` | `dim_cost_center` | direct |
| `ProfitCenter` | `dim_business_unit` | profit center is SAP's responsibility/management unit |
| `Segment` | `dim_department` | reuse existing slot until Dimension Harmonization (PRD, Phase 3) adds native `dim_segment` / `dim_profit_center` |

### 5. Register the source

- Add `sap_s4` to `vars.erp_sources` in `dbt_project/dbt_project.yml` (canonical models pick it up via the `{% for erp in erp_sources %}` loop with no edit).
- Add `Dockerfile`, `metadata.yaml`, `pyproject.toml` for the Airbyte connector image; `run.py` entrypoint.

## Out of Scope

- SAP ECC 6.0 (BSEG/BKPF RFC) — separate connector, PRD 34.
- SAP Business One Service Layer — PRD 35.
- Native canonical `dim_profit_center` / `dim_segment` columns and dimension-registry harmonization — deferred to the Dimension Harmonization task (Phase 3).
- Incremental CDC / Airbyte change-data-capture tuning — covered by Scale Architecture.
- SAP budget extraction: `stg_sap_s4__budget_entries` emits an empty-but-conformant result unless a budget CDS view is configured (no universal SAP GL budget entity).
- Connector Registry Frappe doctype (separate Phase 3 task).

## Acceptance Criteria

1. `python -m source_sap_s4hana spec` returns a valid spec; `check` against a sandbox returns `SUCCEEDED` for both `oauth2_client_credentials` and `basic` auth types.
2. `discover` returns all 8 streams with JSON schemas under `source_sap_s4hana/schemas/`.
3. `pytest source-sap-s4hana/unit_tests/` passes, including an `odata_filter_literal()` injection test and a token-caching test mirroring `test_auth.py` / `test_security_hardening.py`.
4. With `erp_sources: [d365_fo, sap_s4]`, `dbt build` passes all existing tests plus new not_null tests in `_sap_s4__models.yml` with zero regressions to D365-only output.
5. `select distinct erp_source from stg_gl_entries` returns exactly `d365_fo` and `sap_s4`; every `sap_s4` row populates `entity_id`, `posting_date`, `main_account`, and `is_credit`.
6. `test_erp_source_valid.sql` accepts `sap_s4` (already in the canonical `erp_source` enum).
7. A `sap_s4`-sourced trial balance nets to zero debits-minus-credits per `entity_id` + `fiscal_year` (balanced-books test), identical assertion to the D365 adapter.

## Open Questions

- OData v4 service binding paths differ by S/4HANA release (on-prem vs Cloud, `srvd_a2x` vs `srvd`); should `service_path` be fully user-supplied or derived per stream from a release-version config?
- Does the target landscape expose released A2X CDS views (`I_*`) on the OData v4 gateway, or must custom Z-CDS services be allowed via a configurable entity-name override?
- Should `dim_profit_center` and `dim_segment` be added to the canonical schema now (cleaner SAP mapping) or wait for Dimension Harmonization to avoid churning bronze DDL twice?
- Trial balance source: derive period balances from aggregating `I_GLAccountLineItem`, or extract a dedicated balances CDS view (`I_GLAccountBalance`) if available in the landscape?
