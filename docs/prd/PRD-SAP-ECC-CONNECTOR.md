# PRD: SAP ECC 6.0 Connector

**Status:** Not Started
**Date:** 2026-06-13
**Phase:** Phase 3 — Multi-ERP Support (PRD 34)
**Repos:** `konsolidat` (dbt adapter + Airbyte source connector), `konsol` (Frappe orchestration / connector config)

## Problem

- The canonical staging interface (`models/staging/canonical/stg_*`) and the reference D365 F&O adapter (`stg_d365_fo__*`) are complete, but the only ERP that lands data today is D365 F&O. `var('erp_sources')` in `dbt_project.yml` defaults to `['d365_fo']`.
- SAP ECC 6.0 (classic R/3, pre-S/4HANA) is the most common legacy ERP among enterprise consolidation customers. Unlike S/4HANA (PRD 33), ECC exposes **no OData/CDS layer** — GL data lives in classic transparent tables `BSEG` (line items) and `BKPF` (document headers) and must be pulled via RFC/BAPI or IDoc.
- There is no adapter producing `erp_source = 'sap_ecc'`, and no Airbyte source connector for RFC extraction. The `erp_source` enum already reserves `sap_ecc` (canonical-staging-schema.md) but nothing emits it.
- ECC's GL line items (`BSEG`) carry no posting date — that lives only on the header (`BKPF`). Without a header join, every line lacks `posting_date`, `fiscal_year`, `fiscal_period`, and document type, breaking the canonical contract.

## Solution

Build an Airbyte RFC source connector (`source-sap-ecc`) that extracts classic SAP tables via the SAP RFC SDK (`SE16N`-style table reads / `RFC_READ_TABLE` or IDoc), and a dbt adapter (`models/staging/sap_ecc/stg_sap_ecc__*`) that joins `BSEG` line items to `BKPF` headers and maps SAP fields to the canonical 7-model schema, gated by adding `sap_ecc` to `var('erp_sources')`.

## Scope

### 1. Airbyte source connector (`source-sap-ecc`)

Mirror the structure of `source-d365-fno/` (`source.py`, `streams.py`, `spec.yaml`, `metadata.yaml`, `schemas/*.json`, `unit_tests/`). Extraction transport: RFC via `pyrfc` (SAP NW RFC SDK) calling chunked `/SAPDS/RFC_READ_TABLE` or BAPI reads; one Airbyte stream per source table.

| Stream (name) | SAP table | Purpose | Cursor (incremental) |
|---|---|---|---|
| `bseg` | BSEG | GL line items (amount, account, cost center, debit/credit indicator) | — (sliced via BKPF docs) |
| `bkpf` | BKPF | Document headers (posting date, fiscal year/period, doc type, currency) | `CPUDT` (entry date) or `BUDAT` |
| `skat` / `skb1` | SKAT / SKB1 | GL account master + texts (chart of accounts) | — |
| `t001` | T001 | Company codes (legal entities, local currency) | — |
| `tcurr` | TCURR | Exchange rates | `GDATU` (valid-from, inverted date) |
| `t009`/`t009b` | T009 / T009B | Fiscal year variant / period calendar | — |
| `glpct` *(optional)* | GLPCT / FAGLFLEXT | Period totals for trial-balance snapshot | `RYEAR` |

Connector requirements:
- `spec.yaml` connection fields: `app_host`, `system_number` (`sysnr`), `client` (`mandt`), `user`, `password`, `language` (default `EN`), optional `router_string` (SAProuter), `company_codes` (list of `BUKRS` to filter). All credentials `airbyte_secret: true`.
- `check_connection()`: open an RFC connection and call `STFC_CONNECTION` (ping).
- Pagination: `RFC_READ_TABLE` `ROWSKIPS`/`ROWCOUNT` windowing (RFC read has a ~512-byte row width limit — request explicit `FIELDS` lists, never `SELECT *`).
- Incremental: filter `bkpf` by `CPUDT >= state` in the RFC `OPTIONS` WHERE clause; `bseg` is sliced by the `BUKRS`/`BELNR`/`GJAHR` keys of the selected headers.
- `metadata.yaml`: `definitionId: open-epm-sap-ecc`, `dockerRepository: open-epm/source-sap-ecc`, `connectorSubtype: database`, `releaseStage: alpha`, `license: MIT`.

### 2. dbt adapter (`models/staging/sap_ecc/`)

| File | Output |
|---|---|
| `_sap_ecc__sources.yml` | `sap_ecc_raw` source (database `epm_raw`), one table per stream above, `loaded_at_field: _airbyte_extracted_at` |
| `stg_sap_ecc__gl_entries.sql` | canonical `stg_gl_entries` columns — **BSEG ⨝ BKPF on (MANDT, BUKRS, BELNR, GJAHR)** |
| `stg_sap_ecc__accounts.sql` | canonical `stg_accounts` from SKAT/SKB1 |
| `stg_sap_ecc__legal_entities.sql` | canonical `stg_legal_entities` from T001 |
| `stg_sap_ecc__exchange_rates.sql` | canonical `stg_exchange_rates` from TCURR (decode inverted `GDATU` date, apply `UKURS`/`FFACT`/`TFACT` factors) |
| `stg_sap_ecc__fiscal_periods.sql` | canonical `stg_fiscal_periods` from T009/T009B |
| `stg_sap_ecc__trial_balance.sql` | canonical `stg_trial_balance` from GLPCT/FAGLFLEXT (or `null`-model if not extracted) |
| `stg_sap_ecc__budget_entries.sql` | canonical `stg_budget_entries` — empty/passthrough (ECC GL has no native budget register; emit zero rows) |

GL field mapping (`stg_sap_ecc__gl_entries`), output must satisfy the column list in `stg_gl_entries.sql`:

| Canonical column | SAP source | Notes |
|---|---|---|
| `erp_source` | literal `'sap_ecc'` | |
| `record_id` | `concat(BUKRS,'-',BELNR,'-',GJAHR,'-',BUZEI)` | BSEG line key |
| `entity_id` | `BKPF.BUKRS` | company code |
| `posting_date` | `BKPF.BUDAT` | header only — substring to `YYYY-MM-DD` |
| `fiscal_year` | `BKPF.GJAHR` | |
| `fiscal_period` | `BKPF.MONAT` | posting period |
| `main_account` | `BSEG.HKONT` | GL account |
| `amount` | `BSEG.DMBTR` signed by `SHKZG` | local-currency amount; `H`=credit (negate), `S`=debit |
| `transaction_currency` | `BKPF.WAERS` | document currency |
| `transaction_currency_amount` | `BSEG.WRBTR` | doc-currency amount |
| `description` | `BSEG.SGTXT` (fallback `BKPF.BKTXT`) | line/header text |
| `journal_number` | `BKPF.BELNR` | document number |
| `posting_type` | `BKPF.BLART` | document type |
| `ledger_account` | `BSEG.HKONT` | |
| `is_credit` | `1` if `BSEG.SHKZG = 'H'` else `0` | |
| `dim_cost_center` | `BSEG.KOSTL` | |
| `dim_department` | `BSEG.PRCTR` | profit center → department dim |
| `dim_business_unit` | `BSEG.GSBER` | business area |
| `_loaded_at` / `_raw_id` | `_airbyte_extracted_at` / `_airbyte_raw_id` | |

### 3. Enablement & orchestration

- Add `sap_ecc` to `vars.erp_sources` in `dbt_project.yml`; canonical `stg_*` models then UNION the new adapter automatically (no canonical-model edits).
- Register the connector in `konsol` so an admin can configure SAP ECC credentials and trigger Extract + dbt Build through the existing pipeline orchestration (same path used by the Excel add-in).

## Out of Scope

- SAP S/4HANA (OData/CDS) — separate connector, PRD 33.
- SAP Business One — separate connector, PRD 35.
- Sub-ledger detail (AP/AR/Fixed Assets); only GL (`BSEG`/`BKPF`) and masters are extracted.
- IDoc-based extraction transport (RFC table read is the primary path; IDoc deferred unless RFC is unavailable).
- New GAAP/parallel-ledger handling (classic ECC single-ledger assumed; `RLDNR` filtering deferred).
- Dimension harmonization across ERPs (separate PRD 3.8) and ClickHouse cluster sharding.

## Acceptance Criteria

1. `source-sap-ecc` `check()` returns `SUCCEEDED` against a test SAP ECC client and `discover` lists the streams in §1.
2. `read` on `bseg` and `bkpf` returns records; RFC reads use explicit `FIELDS` lists (no full-width row > 512 bytes errors). Unit tests in `unit_tests/` mirror `source-d365-fno` coverage (source, streams, auth/connection, security hardening) and pass under pytest.
3. With `erp_sources: [d365_fo, sap_ecc]`, `dbt build --select staging.sap_ecc+ staging.canonical` succeeds; `stg_gl_entries` contains rows with `erp_source = 'sap_ecc'`.
4. Every `stg_sap_ecc__*` model emits exactly the canonical column set for its target model (verified by `_canonical__models.yml` not_null tests and `test_erp_source_valid.sql` accepting `sap_ecc`).
5. For any ECC document, `sum(amount)` across its `BSEG` lines = 0 (debits net credits) — verified by a dbt test on `stg_sap_ecc__gl_entries` grouped by `journal_number`, `entity_id`, `fiscal_year`.
6. No `BSEG` line is emitted without a matched `BKPF` header (inner join); a test asserts zero null `posting_date` in `stg_sap_ecc__gl_entries`.
7. Adding `sap_ecc` requires zero edits to canonical models, bronze, silver, or gold; full `dbt build` passes with no regressions to existing tests.

## Open Questions

- RFC table read vs. a custom ABAP extractor function module: `RFC_READ_TABLE` is simplest but rate/width-limited at high volume — is a customer-installed ABAP Z-extractor acceptable for production-scale BSEG pulls?
- ECC `DMBTR` is stored without decimals for some currencies (CURR field + `TCURX`) — apply currency-decimal normalization in the adapter or in bronze?
- Trial balance: extract from `GLPCT`/`FAGLFLEXT` totals tables, or derive entirely from `stg_gl_entries` (skip the TB stream)?
- Profit center vs. business area as the canonical `dim_department`/`dim_business_unit` mapping — confirm per first customer's chart of accounts.
