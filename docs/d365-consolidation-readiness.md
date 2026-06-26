# Konsolidat — D365 → Consolidation: Readiness & Gap Analysis

_State of the local `konsolidat.local` deployment, probed via **konsol-cli** (api backend, pure HTTP) and read-only ClickHouse inspection. 2026-06-23._

!!! note "Point-in-time snapshot (2026-06-23) — partly superseded"
    This is a dated readiness analysis, kept as a record of the deployment at the time. Since then: the demo dataset was replaced by the **Contoso Group (`GROUP_CORP`)** seed (not "Alpine Manufacturing"), and two D365 connectors (`CONN-00001`, `CONN-00002`) have been registered — so the "empty connector registry" finding no longer holds. The two-plane model and the real-D365 gap analysis below remain accurate.

## TL;DR

- The **config / model plane is fully built** (dimensions, measures, fact tables published; consolidation groups seeded).
- The **konsol Connector registry is empty** — no registered ERP/D365 source.
- **But `epm_raw` already holds a coherent demo D365 dataset** (loaded via a mock Airbyte source, with `_airbyte_*` metadata), and **dbt sources directly from `epm_raw`**.
- **→ We can run a full consolidation on the existing demo data right now**, without a real D365 connection.
- The only gap for pulling from a **real** D365 is a registered `Connector` + Azure AD credentials.

## The two planes

| Plane | Owner | State |
|---|---|---|
| **Config / model** | konsol-cli (config plane, HTTP API) | ✅ Complete |
| **Extract** (D365 → `epm_raw`) | konsol `Connector` + Airbyte (app-setup/infra) | ⚠️ No registered connector; `epm_raw` pre-loaded with demo data |
| **Transform** (`epm_raw` → gold → consolidation) | dbt | ✅ Wired to source from `epm_raw` |

## 1. Config / model plane — built (konsol-cli evidence)

`konsol schema status`:
- Dimension: **3 published** · Measure: **13 published** · Fact Table: **6 published**
- Pending build: `PBR-00001` (scope `staging`, state `Approved`, risk `low`, trigger `Allocation Rule ALLOC_001`)

`konsol fact list` — 6 published facts; the consolidation source is **`gl_journal_entries`** (Source Type `ERP GL`, scenario `actuals`). Others: `area_sqm`, `budget_input`, `headcount`, `revenue_by_product`, `variance_analysis`.

## 2. Extract plane — empty registry, but demo data present

- `konsol connector list` → **"No connectors found."**
- `konsol source list` → **"(none — add an enabled Connector)"**

So no konsol-registered ERP source. However, `epm_raw` already contains a **D365 F&O demo dataset** for an **"Alpine Manufacturing"** group (D365 OData "BiEntity" table shapes, ~1,638 rows, `_airbyte_extracted_at: 2024-12-31` → loaded through the mock `source-d365-fno` Airbyte source).

### `epm_raw` inventory
- **GL / ledger:** `GeneralJournalAccountEntryBiEntities` 782 · `GeneralJournalEntryBiEntities` 379 · `TrialBalanceFiscalYearSnapshots` 54 · `Ledgers` 3
- **Chart of accounts / dims:** `MainAccounts` 24 · `MainAccountCategories` 13 · `FinancialDimensionValues` 12 · `DimensionAttributes` 3 · `ConsolidateAccountGroups` 1
- **Budget:** `BudgetRegisterEntries` 288
- **FX:** `ExchangeRates` 72 · `ExchangeRateTypes` 3 · `ExchangeRateCurrencyPairs` 0
- **Entities / calendar:** `LegalEntities` 3 · `FiscalCalendarYears` 1 · `FiscalCalendars` 0
- **Empty / Airbyte artifacts:** `GeneralLedgerActivities` 0 + 3 hash-suffixed temp tables

### Legal entities (consolidation scope)
1. **Alpine Manufacturing HQ** (`AMHQ`) — 🇨🇭 CH (parent)
2. **Alpine Manufacturing DE** (`AMDE`) — 🇩🇪 DE
3. (third entity)

Multi-currency (CHF/EUR), 3-entity group, GL + FX + consolidate-account-groups → enough to consolidate end-to-end.

## 3. Transform plane — dbt sources from `epm_raw`

The D365 staging models read straight from the raw layer:

```sql
-- dbt_project/models/staging/d365_fo/stg_d365_fo__gl_journal_entries.sql
select * from {{ source('d365_raw', 'GeneralJournalAccountEntryBiEntities') }}
select * from {{ source('d365_raw', 'GeneralJournalEntryBiEntities') }}
```

`d365_raw` (declared in `models/staging/d365_fo/_d365_fo__sources.yml`) maps to the `epm_raw` schema. So `epm_raw` → `stg_d365_fo__*` → silver → gold → consolidation is a live path.

## 4. Can we work with `epm_raw`? — Yes

Because dbt sources directly from `epm_raw`, the demo Alpine Manufacturing D365 data can be run through to a consolidated result **without any real D365 connection**. This is the right way to exercise/validate the consolidation logic now.

## 5. The real-D365 gap (when you want live data)

To replace the demo data with a real F&O pull:
1. **Register a D365 `Connector`** (`erp_type = d365`). The extract profile needs: `environment_url`, `tenant_id`, `extract_client_id`, `extract_client_secret`, `legal_entities`, page-size/cross-company options.
2. **Enable it** → appears in `source list` / dbt `vars.erp_sources`.
3. **Provision + run Airbyte** (`provision_connector_airbyte`) → `epm_raw`.
4. **`konsol schema apply`** → regenerate dbt vars + ClickHouse DDL.
5. **Build** → Pipeline Build Request runs dbt; consolidation recomputes on real data.

**True prerequisite:** an **Azure AD app registration** with OData / Data-Management access to the F&O environment, plus the legal-entity list. Everything downstream is already in place.

## Appendix — konsol-cli commands used (api backend, no docker)

```bash
konsol --backend api --url http://localhost:8069 --site konsolidat.local schema status
konsol ... connector list
konsol ... source list
konsol ... fact list
```

Connection: `~/.config/konsol/config.toml` (backend=api) + `~/.config/konsol/secrets.env` (API key/secret).
