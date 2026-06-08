# Open EPM Architecture

## Stack (updated 2026-06-08)
- **ClickHouse**: Analytical DB (Docker, ports 8123/9000, user: default, pw: open_epm_dev)
- **Airbyte**: Data ingestion (Kind/Docker via abctl, port 8000, v2.1.0)
- **Frappe/konsol**: API proxy + pipeline orchestration + EPM doctypes (bare metal, port 8069, site: epm.local, repo: grynn-in/konsol)
- **dbt**: Data transformation (local venv, dbt-clickhouse 1.10.0)
- **Cube.js**: Needed for production (50-100 concurrent users — caching + pre-aggregations). Not yet re-added.
- ~~Dagster, FastAPI, Streamlit~~ — replaced by Frappe konsol app

## Data Flow (confirmed 2026-06-08)
D365 F&O (OData) → Airbyte → epm_raw → dbt staging (stg_d365__*) → epm_bronze → epm_silver → epm_gold → Frappe/konsol API → Excel

## ClickHouse Databases
- `epm_raw` — Airbyte landing (17 tables, 1.3M rows, PascalCase D365 entity names, has _airbyte_* columns)
- `epm_bronze` — dbt bronze models (15 bronze_* tables, 670K rows, cleaned/typed from staging)
- `epm_silver` — dbt silver models (8 tables, 6.5M rows, joined/enriched)
- `epm_gold` — dbt gold models (32 tables, 1.2M rows, analytical outputs)
- `epm_staging` — Write-back staging (budget input, scenarios — nearly empty)

## Konsol Frappe App (grynn-in/konsol)
- EPM module: 12 doctypes (Scenario Definition, Dimension, Measure, Fiscal Period, Spread Profile, Allocation Rule, Allocation Driver, Consolidation Group, IC Elimination Rule, Consolidation Adjustment, Budget Input, Budget Input Child)
- clickhouse.py: sync_table(), sync_doctype() — TRUNCATE + INSERT on save
- dbt_config.py: regenerate_vars() — writes dbt_project.yml vars from Frappe docs
- api.py: epm_value, epm_batch (read), budget_save, budget_save_batch, budget_cell_save (write-back)
- EPMSAVE(): immediate write-back VBA function, layer is required param (not auto-detected), skip-unchanged cache
- D365 write-back: roadmap Phase 3 — on Budget approval, POST to D365 BudgetRegisterEntry OData entities
- Budget workflow: Draft → Submitted → Approved/Rejected, 4 roles (Submitter/Controller/Manager/Approver)
- Budget layers: base + challenge + management + board = effective budget
- scenario_id: optional filter on epm_value/epm_batch (9th param, only gold_spread_budget)
- 158 TDD tests across 10 test files

## dbt Structure (60 models, 16 sources)
- 15 staging models (source: d365_raw → epm_raw, parse JSON dimensions, join headers)
- 15 bronze models (ref: stg_d365__* → epm_bronze, cast types)
- 7 silver models
- ~22 gold models
- 10 seeds (allocation rules, spread profiles, etc.)
- 81 tests
- Configurable dimension registry (vars.dimensions in dbt_project.yml)
- DB adapter macros (ClickHouse-specific functions abstracted)

## D365 Sandbox
- Tenant: 13588042-fe43-45bb-8ce1-83b2e6dd126c
- URL: https://bizapps2.sandbox.operations.dynamics.com
- 144 legal entities (USMF, DEMF, GBMF, JPMF, CHBK, CMBC, TDBF, etc.)
- OAuth client credentials in .env
