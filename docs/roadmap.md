# Konsolidat — Roadmap

*Last updated: 2026-06-09*

## Status Summary

| Area | Status |
|---|---|
| Data pipeline (Bronze → Silver → Gold) | **Done** — 44 dbt models, 26 tests |
| Consolidation (FX, IC elimination, CTA, NCI) | **Done** — IFRS/GAAP compliant |
| Hierarchy, equity method, acquisition/disposal | **Done** — PRD-8 through PRD-22 |
| Allocations (multi-step cascade, reciprocal, tiered) | **Done** — dynamic N-step engine |
| Budget write-back | **Done** — EPMSAVE() from Excel + Frappe API |
| Scenario management | **Done** — budget/forecast/whatif via API |
| Variance analysis | **Done** — actual vs budget with favorable logic |
| Excel VBA integration | **Done** — =EPM() + 5 functions, ODBC + REST |
| Frappe app (konsol) | **Done** — DocTypes, ClickHouse sync, background jobs |
| Docs site (MkDocs Material) | **Done** — konsolid.at, 31+ pages |
| Custom domain | **Done** — konsolid.at on GitHub Pages |
| FastAPI / Streamlit / Dagster | **Retired** — replaced by Frappe konsol app |
| One-click deploy | **Not started** |
| Multi-ERP (SAP, ERPNext) | **Not started** |
| Dynamic schema (dimensions, measures, facts) | **Not started** |
| Security / Entra ID SSO | **Not started** |
| Excel Online Add-in (Office.js) | **Done** — Task pane add-in, pipeline orchestration, Frappe session auth |
| Cash flow statement | **Not started** |
| Multi-GAAP | **Not started** |
| Rolling forecasts | **Not started** |

---

## Phase 1: One-Click Deploy (~3 days)

Full docker-compose stack + single deploy script. Goal: `git clone && ./deploy.sh` gets a working instance.

### 1.1 Full Docker Compose (1.5 days)

- [ ] Add services: Frappe (bench), PostgreSQL/MariaDB, Redis (cache + queue), Frappe worker
- [ ] ClickHouse already containerised — wire into same compose network
- [ ] Airbyte via `abctl` or optional compose profile
- [ ] Init containers: ClickHouse schema (`init-db.sql`), Frappe site creation, dbt seed + build
- [ ] Volume management for persistent data (ClickHouse, database, Redis)
- [ ] Health checks for all services

### 1.2 Deploy Script (1 day)

- [ ] `deploy.sh` — copies `.env.example`, prompts for passwords, runs compose up, waits for health, runs init
- [ ] First-run detection: seed data vs. upgrade (dbt build only)
- [ ] TLS via Caddy reverse proxy (auto-cert or self-signed for local)

### 1.3 Documentation (0.5 days)

- [ ] Update `docs/admin-guide/deployment-guide.md` with one-click path
- [ ] Quick-start README section: 3 commands to running instance
- [ ] Environment variable reference

---

## Phase 2: Dynamic Schema — Dimensions, Measures & Facts (~5 days)

Make the data model fully registry-driven from Frappe. Adding a dimension, measure, or fact table should be a UI operation in Frappe Desk, not a code change across 6 files.

### Current state (hardcoded)

| Concept | What it is | Example | Where hardcoded |
|---|---|---|---|
| **Dimension** | Attribute to slice by | Cost Center, Department, Project | ClickHouse columns, API params, Budget Input doctype, dbt macros |
| **Measure** | Numeric value to aggregate | period_net_amount, opening_balance, ytd_amount | dbt macros, API column mapping, Excel function `measure` param |
| **Fact** | Transactional grain / source table | GL Journal Entries, Budget Input, Allocation Results | dbt models, ClickHouse staging tables, Airbyte sync config |

### 2.1 Dimension Registry (1 day)

- [ ] Frappe `Dimension` doctype becomes authoritative — on save, auto-generates:
  - ClickHouse `ALTER TABLE ADD COLUMN` for all staging/reporting tables
  - Entry in `dbt_project.yml` `vars.dimensions` (or dbt vars override)
  - Budget Input doctype field (dynamic via Frappe custom fields API)
- [ ] Validation: dimension name must be `dim_*`, unique, no reserved words
- [ ] Source mapping per ERP: D365 JSON path, SAP field name, ERPNext fieldname
- [ ] Allocation engine uses `allocation_role` from dimension config, not hardcoded column names

### 2.2 Measure Registry (1 day)

- [ ] Frappe `Measure` doctype: `name`, `column_name`, `aggregation` (sum/avg/last), `label`, `favorable_direction` (debit/credit)
- [ ] On save, auto-generates:
  - dbt `vars.measures` entries (drives `{{ measure_select() }}` macros)
  - ClickHouse columns on gold tables
  - API response includes only active measures
- [ ] Default measures pre-seeded: `period_net_amount`, `opening_balance`, `closing_balance`, `ytd_amount`, `debit_amount`, `credit_amount`
- [ ] Custom measures: e.g. `headcount`, `revenue_per_sqm` — derived via SQL expression field on the doctype

### 2.3 Fact Registry (1.5 days)

- [ ] Frappe `Fact Table` doctype: `name`, `source_type` (ERP GL / Budget / Statistical / Sub-ledger), `grain` description, `refresh_frequency`
- [ ] Core facts (pre-seeded, always present):
  - **GL Journal Entries** — debits/credits by account/period/entity (the universal financial fact)
  - **Budget Input** — budget submissions per cell
  - **Allocation Results** — derived output from allocation engine
- [ ] Statistical facts (customer-configurable):
  - **Headcount** — employees per cost center per period (for allocation drivers)
  - **Area (sqm)** — square metres per cost center (for facilities allocation)
  - **Revenue by Product** — for revenue-based allocation
- [ ] Sub-ledger facts (for detailed reporting):
  - **Accounts Payable** — invoice-level detail for cash flow
  - **Fixed Assets** — asset register for depreciation / investing cash flow
  - **Accounts Receivable** — aging for working capital analysis
- [ ] Each Fact Table defines: required dimensions, required measures, ClickHouse table name, dbt model name
- [ ] On save: generates ClickHouse staging table DDL + dbt source definition
- [ ] Statistical facts replace the current `allocation_drivers` seed with a proper queryable fact table

### 2.4 API Generalisation (1 day)

- [ ] Replace hardcoded `cost_center`, `department` params with generic `dimensions` dict
- [ ] `=EPM("USMF", 2024, "Q1", "401100", dimensions={"cost_center": "CC001", "project": "P01"})`
- [ ] `measure` parameter validates against active Measure registry
- [ ] New `fact` parameter: defaults to GL, but can query budget or statistical facts
- [ ] Backward-compatible: old named params still work, mapped internally
- [ ] ClickHouse query builder reads active dimensions/measures/facts from registry

### 2.5 Source Layer Abstraction (0.5 days)

- [ ] dbt macro `{{ dim_extract_from_source() }}` reads dimension list and generates extraction SQL per ERP
- [ ] D365: auto-extract from `LedgerDimensionValuesJson` by `source_column` name
- [ ] SAP/ERPNext: each connector provides its own dimension mapping (see Phase 3)
- [ ] Fact-specific source macros: GL extraction vs. budget extraction vs. statistical extraction

---

## Phase 3: Multi-ERP Support — SAP + ERPNext (~5 days)

Konsolidat currently extracts from D365 F&O only. Abstract the source layer so any ERP can feed the same silver/gold models.

### 3.1 ERP-Agnostic Bronze Schema (2 days)

- [ ] Define canonical bronze interface: `entity_id`, `fiscal_year`, `fiscal_period`, `main_account`, `debit`, `credit`, `currency`, `dimensions[]`
- [ ] D365 connector (existing): map `GeneralJournalAccountEntry` → canonical schema
- [ ] SAP connector: map FI line items (BSEG/BKPF or S/4HANA CDS views) → canonical schema
- [ ] ERPNext connector: map `GL Entry` doctype → canonical schema
- [ ] Each connector is an Airbyte source + one dbt staging model

### 3.2 Connector Abstraction (1.5 days)

- [ ] Frappe `ERP Connection` doctype: type (D365/SAP/ERPNext), credentials, entity mapping
- [ ] Airbyte connection auto-provisioning from ERP Connection config
- [ ] dbt source selector: `{{ source('bronze_' ~ erp_type, 'gl_entries') }}`
- [ ] Silver layer is ERP-agnostic — all connectors produce identical output

### 3.3 ERPNext Native Integration (0.5 days)

- [ ] ERPNext bonus: direct Frappe-to-Frappe API (no Airbyte needed)
- [ ] `hooks.py` event on GL Entry submit → write to ClickHouse bronze directly
- [ ] Real-time consolidation for ERPNext customers

### 3.4 Docs & Landing Page (1 day)

- [ ] Update konsolid.at: "Works with D365, SAP, and ERPNext"
- [ ] Connector setup guides for each ERP
- [ ] Update marketing blurb (PPTX) with multi-ERP positioning
- [ ] Architecture diagram showing pluggable source layer

---

## Phase 4: Security & Entra ID SSO (~2 days)

### 4.1 Entra ID Integration (1 day)

- [ ] Register Konsol in Microsoft Entra ID (OAuth2 / OpenID Connect)
- [ ] Map Entra ID groups to Frappe roles (Reader, Planner, Controller, Admin)
- [ ] Test SSO login flow

### 4.2 Reverse Proxy & TLS (0.5 days)

- [ ] Caddy in docker-compose: auto-cert TLS, CORS for Excel Online
- [ ] Rate limiting: 100 req/min per user

### 4.3 ClickHouse Network Isolation (0.5 days)

- [ ] ClickHouse on Docker internal network only (no host port bindings in production)
- [ ] Verify: no ClickHouse ports reachable from public internet

---

## Phase 5: Excel Online Add-in ~~(~3 days)~~ DONE

Task pane add-in built and deployed. Source: `excel-addin/`, served from Frappe `public/excel-addin/`.

- [x] Office.js Task Pane app (manifest.xml, taskpane.html/js/css, icons)
- [x] Frappe session-based authentication (login/logout via cookie)
- [x] Pipeline orchestration: trigger Extract + dbt Build, poll status (5s interval)
- [x] Status display: Queued/Extracting/Transforming/Success/Failed badges
- [x] Deployed to Frappe static assets, sideloadable via manifest.xml
- [x] Documentation: README + user guide + architecture diagram

**Not included** (by design — VBA handles data):
- No custom functions (=EPM() stays in VBA for desktop, Office.js for pipeline control)
- No MSAL/OAuth (uses Frappe session cookies instead)

---

## Phase 6: Analytical Gaps (~2 weeks)

### 6.1 Cash Flow Statement (2–3 days)

- [ ] `gold_cash_flow_indirect.sql` — derive from balance sheet delta method
- [ ] Categories: Operating, Investing, Financing
- [ ] Account mapping seed: `cash_flow_categories.csv`
- [ ] Consolidated cash flow (after FX translation)
- [ ] Tests: operating + investing + financing = net change in cash

### 6.2 Multi-GAAP / Dual Reporting (1 week)

- [ ] `reporting_standard` dimension (LOCAL_GAAP, IFRS)
- [ ] Separate adjustment rules per standard
- [ ] Gold models produce one output per standard
- [ ] Tests: each standard balances independently

### 6.3 Rolling Forecasts (2–3 days)

- [ ] 12-month forward window, shifts monthly
- [ ] Actual for closed periods + forecast for open periods
- [ ] Scenario type `rolling`

---

## Phase 7: Production Hardening (~3 days)

- [ ] ClickHouse backup automation (scheduled snapshots to Azure Blob / S3)
- [ ] Monitoring: ClickHouse query latency + Frappe response times (Prometheus + Grafana)
- [ ] Alerting: email/Slack on pipeline failure or dbt test failure
- [ ] Load testing: simulate 50 concurrent Excel users
- [ ] Runbook: monthly close process
- [ ] Disaster recovery procedure

---

## Effort Summary

| Phase | Effort | Dependencies |
|---|---|---|
| **Phase 1:** One-click deploy | ~3 days | None |
| **Phase 2:** Dynamic schema (dimensions, measures, facts) | ~5 days | None |
| **Phase 3:** Multi-ERP (SAP + ERPNext) | ~5 days | Phase 2 (dimension abstraction) |
| **Phase 4:** Security & SSO | ~2 days | Phase 1 |
| **Phase 5:** Excel Online Add-in | ~~3 days~~ **Done** | — |
| **Phase 6:** Analytical gaps | ~2 weeks | Phase 2 (dimensions) |
| **Phase 7:** Production hardening | ~3 days | Phase 1 |
| **Total** | **~7 weeks** | |

Phases 1 and 2 can run in parallel. Phase 3 depends on Phase 2 (schema abstraction). Phases 4–7 can overlap.
