# Open EPM — Roadmap & Remaining Activities

*Last updated: 2026-06-07*

## Status Summary

| Area | Status |
|---|---|
| Data pipeline (Bronze → Silver → Gold) | **Done** — 37 dbt models, 21 tests |
| Consolidation (FX, IC elim, CTA, NCI) | **Done** — IFRS/GAAP compliant, tested |
| Allocations (multi-step cascade) | **Done** — 3-step with driver support |
| Budget write-back (FastAPI) | **Done** — 11 endpoints, staging tables |
| Scenario management | **Done** — budget/forecast/whatif via API |
| Variance analysis | **Done** — actual vs budget with favorable logic |
| Excel integration (desktop ODBC) | **Done** — Cube SQL + VBA macros |
| Admin UI (Streamlit) | **Done** — 4 pages |
| Orchestration (Dagster) | **Done** — Airbyte + dbt asset graph |
| Security / auth / RBAC | **Not started** |
| Frappe migration | **Not started** |
| Excel Online Add-in | **Not started** |
| Cash flow statement | **Not started** |
| Multi-GAAP | **Not started** |
| Rolling forecasts | **Not started** |

---

## Phase 1: Frappe Migration (~5 days)

Replace FastAPI + Streamlit + CSV seeds with Frappe. This closes the auth, workflow, audit, and web UI gaps in one move.

### 1.1 Frappe App Scaffold (1 day)

- [ ] `bench init open-epm-bench`
- [ ] `bench new-app open_epm`
- [ ] Add ClickHouse connection module (`clickhouse-connect`)
- [ ] Add Frappe app to `docker-compose.yml` (Frappe + MariaDB + Redis + workers)
- [ ] Verify Frappe Desk loads at `localhost:8000`

### 1.2 DocTypes — Config (1–2 days)

Replace CSV seeds with Frappe DocTypes. Each DocType gets auto-generated REST API, list/form views, versioning, and audit trail.

- [ ] **Scenario** — scenario_id, name, type (budget/forecast/whatif), base_scenario, is_active, created_by
- [ ] **Consolidation Group** — group_name, entity_id, ownership_pct, reporting_currency, is_active
- [ ] **IC Elimination Rule** — rule_id, debit_account, credit_account, description
- [ ] **Allocation Rule** — step_order, rule_id, source_account, target_account, driver_type, source_cost_center
- [ ] **Allocation Driver** — driver_type, cost_center, fiscal_period, fiscal_year, driver_value
- [ ] One-time migration: load existing CSV seed data into DocTypes

### 1.3 DocTypes — Budget Write-back (1 day)

- [ ] **Budget Entry** — entity, year, period, account, cost_center, department, amount, scenario_id, submitted_by
- [ ] Workflow: Draft → Submitted → Approved (controller approves)
- [ ] On Approve: server script writes approved rows to ClickHouse `epm_staging.budget_input`
- [ ] Port `/api/v1/epm/value`, `/api/v1/epm/batch`, `/api/v1/epm/members` to Frappe whitelisted API methods

### 1.4 Config Sync to ClickHouse (0.5 days)

- [ ] Server script on Consolidation Group save → write to `epm_staging.consolidation_groups`
- [ ] Server script on IC Rule save → write to `epm_staging.ic_elimination_rules`
- [ ] Server script on Allocation Rule/Driver save → write to `epm_staging.allocation_rules` / `allocation_drivers`
- [ ] Trigger Dagster dbt rebuild after config change (webhook or Dagster sensor)

### 1.5 Retire FastAPI + Streamlit (0.5 days)

- [ ] Remove `api/` directory
- [ ] Remove `streamlit/` directory
- [ ] Remove FastAPI and Streamlit from `docker-compose.yml`
- [ ] Update `Makefile` targets
- [ ] Update `README.md`

---

## Phase 2: Security & Entra ID SSO (~2 days)

### 2.1 Entra ID Integration (1 day)

- [ ] Register Open EPM as an app in Microsoft Entra ID (same tenant as D365)
- [ ] Configure Frappe Social Login Key for Entra ID (OAuth2 / OpenID Connect)
- [ ] Map Entra ID groups to Frappe roles (Reader, Planner, Controller, Admin)
- [ ] Test SSO login flow from browser

### 2.2 Reverse Proxy & TLS (0.5 days)

- [ ] Add Caddy to `docker-compose.yml`
- [ ] Configure Caddyfile: TLS auto-cert, reverse proxy to Frappe, CORS headers
- [ ] Whitelist `*.officeapps.live.com` for Excel Online
- [ ] Rate limiting: 100 req/min per user

### 2.3 ClickHouse Network Isolation (0.5 days)

- [ ] ClickHouse listens on Docker internal network only (remove host port bindings)
- [ ] Cube SQL API: internal network or VPN-only for desktop ODBC users
- [ ] Verify: no ClickHouse ports reachable from public internet

---

## Phase 3: Excel Online Add-in (~3 days)

### 3.1 Add-in Scaffold (1 day)

- [ ] `npx yo office --type excel-functions-shared` → TypeScript project
- [ ] Register custom functions: `EPM.VALUE`, `EPM.CONSOLIDATED`, `EPM.VARIANCE`, `EPM.MEMBERS`, `EPM.SUBMIT`
- [ ] MSAL.js integration: acquire Entra ID token, pass as Bearer header
- [ ] Test locally with `npm start` → Excel sideload

### 3.2 API Integration (1 day)

- [ ] `EPM.VALUE()` → `GET /api/method/open_epm.api.get_value`
- [ ] `EPM.CONSOLIDATED()` → `GET /api/method/open_epm.api.get_consolidated`
- [ ] `EPM.VARIANCE()` → `GET /api/method/open_epm.api.get_variance`
- [ ] `EPM.MEMBERS()` → `GET /api/method/open_epm.api.get_members`
- [ ] `EPM.SUBMIT()` → `POST /api/method/open_epm.api.submit_budget`
- [ ] Batch optimization: coalesce multiple `EPM.VALUE()` calls into single batch request during recalc
- [ ] Result caching: 5-minute TTL per dimension combination

### 3.3 Deployment (1 day)

- [ ] Build production add-in manifest (manifest.xml)
- [ ] Upload to Microsoft 365 admin center for org-wide deployment
- [ ] Test in Excel Online (browser), Excel Desktop (Windows/Mac), Excel iPad
- [ ] Write user guide: `docs/excel-online-guide.md`

---

## Phase 4: Analytical Gaps (~2 weeks)

### 4.1 Cash Flow Statement (2–3 days)

- [ ] `gold_cash_flow_indirect.sql` — derive from BS delta method (period-over-period balance changes)
- [ ] Categories: Operating (P&L adjustments), Investing (fixed asset changes), Financing (debt/equity changes)
- [ ] Account mapping seed: `cash_flow_categories.csv` — maps main accounts to CF categories
- [ ] Consolidated cash flow (after FX translation)
- [ ] Add Cube schema + Excel table endpoint
- [ ] Tests: CF operating + investing + financing = net change in cash

### 4.2 Multi-GAAP / Dual Reporting (1 week)

- [ ] Add `reporting_standard` dimension to gold models (e.g. `LOCAL_GAAP`, `IFRS`)
- [ ] Separate adjustment rules per standard (e.g. different depreciation, lease treatment)
- [ ] `consolidation_adjustments` seed gets `reporting_standard` column
- [ ] `gold_consolidated_trial_balance` produces one output per standard
- [ ] Cube schema + Excel function support `=EPM.VALUE(..., "IFRS")` vs `=EPM.VALUE(..., "LOCAL")`
- [ ] Tests: each standard balances independently

### 4.3 Rolling Forecasts (2–3 days)

- [ ] `gold_rolling_forecast.sql` — 12-month forward window, shifts monthly
- [ ] Logic: actual for closed periods + forecast for open periods
- [ ] Forecast version management: auto-create next month's forecast from prior + actuals
- [ ] Scenario type `rolling` in addition to `budget`/`forecast`/`whatif`
- [ ] Tests: rolling window always covers exactly 12 periods

---

## Phase 5: Production Hardening (~3 days)

- [ ] ClickHouse backup automation (scheduled snapshots to Azure Blob / S3)
- [ ] Dagster alerting: email on pipeline failure
- [ ] Monitoring: ClickHouse query latency + Frappe response times (Prometheus + Grafana or Frappe's built-in)
- [ ] Load testing: simulate 50 concurrent Excel users with `EPM.VALUE()` calls
- [ ] Documentation: runbook for monthly close process
- [ ] Documentation: disaster recovery procedure

---

## Effort Summary

| Phase | Effort | Dependencies |
|---|---|---|
| **Phase 1:** Frappe migration | ~5 days | None |
| **Phase 2:** Security & SSO | ~2 days | Phase 1 |
| **Phase 3:** Excel Online Add-in | ~3 days | Phase 1 + 2 |
| **Phase 4:** Analytical gaps | ~2 weeks | Phase 1 (config sync) |
| **Phase 5:** Production hardening | ~3 days | Phase 1–3 |
| **Total** | **~5 weeks** | |

Phases 1–3 can be done sequentially in ~2 weeks. Phase 4 can run in parallel with Phase 3. Phase 5 follows all others.
