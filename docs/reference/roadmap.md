# Open EPM — Roadmap

*Last updated: 2026-06-08*

## Status Summary

| Area | Status |
|------|--------|
| Data pipeline (Bronze → Silver → Gold) | **Done** — 44 dbt models, 26 tests, 11 seeds |
| Consolidation (FX, IC elim, CTA, NCI) | **Done** — IFRS/GAAP compliant, fully tested |
| Allocations (multi-step cascade) | **Done** — 3-step with headcount/sqm/revenue drivers |
| Budgeting & spreading | **Done** — Annual input, configurable profiles, 12-period spread |
| Variance analysis | **Done** — Actual vs budget with favorable logic, YTD, quarterly |
| Scenario management | **Done** — Actuals/budget/forecast/whatif via seeds |
| Excel VBA integration | **Done** — 5 functions, 7 macros, batch API, period ranges |
| Frappe API (Konsol) | **Done** — 3 endpoints (health, epm_value, epm_batch) |
| Frappe EPM Settings | **Done** — ClickHouse, Airbyte, dbt config |
| Excel Task Pane (pipeline control) | **Done** — Office.js add-in, login, trigger, status |
| Prior year comparison | **Done** — YoY variance model |
| BS movement schedule | **Done** — Opening/movement/closing model |
| Documentation | **Done** — 31-file doc suite |
| Entra ID SSO | Not started |
| Excel Online custom functions | Not started |
| Cash flow statement | Not started |
| Multi-GAAP | Not started |
| Rolling forecasts | Not started |
| Budget write-back from Excel | Not started |

---

## Completed

### Core Pipeline
- 14 Bronze models (D365 OData via Airbyte)
- 8 Silver models (cleaned, standardized)
- 22 Gold models (business logic)
- 26 data quality assertion tests
- 11 seed tables for reference data
- Dimension auto-propagation system (3 dimensions, extensible)
- ClickHouse adapter macros for portable SQL

### Financial Logic
- Multi-entity consolidation with FX translation (closing/average rates)
- CTA calculation and posting
- NCI/Group amount split by ownership %
- Intercompany elimination (3 rules)
- Top-side consolidation adjustments
- Fully consolidated TB (4-layer union)
- Multi-step cascading cost allocations (3 steps)
- Budget spreading with configurable profiles
- Actual vs budget variance with favorable/unfavorable logic
- YTD running totals (trial balance and consolidated)
- Quarterly and half-yearly aggregations
- Prior year comparison with YoY variance
- Balance sheet movement schedule

### Integration
- Frappe/Konsol API: health, single value, batch query
- EPM Settings DocType (ClickHouse, Airbyte, dbt config)
- VBA module: EPM, EPM_BUDGET, EPM_VARIANCE, EPM_DEBIT, EPM_CREDIT
- Office.js task pane for pipeline orchestration
- Period range support (Q1–Q4, H1/H2, FY)

---

## Upcoming

### Phase 1: Security & Entra ID SSO (~2 days)

- [ ] Register Konsol in Microsoft Entra ID (same tenant as D365)
- [ ] Configure Frappe Social Login Key for Entra ID (OAuth2 / OpenID Connect)
- [ ] Map Entra ID groups to Frappe roles (Reader, Planner, Controller, Admin)
- [ ] TLS via Caddy with auto Let's Encrypt
- [ ] CORS whitelist for `*.officeapps.live.com`
- [ ] Rate limiting: 100 req/min per user

### Phase 2: Excel Online Add-in (~3 days)

- [ ] TypeScript + Office.js custom functions: `EPM.VALUE`, `EPM.CONSOLIDATED`, `EPM.VARIANCE`, `EPM.MEMBERS`, `EPM.SUBMIT`
- [ ] MSAL.js integration for Entra ID token-based auth
- [ ] Batch coalescing during recalc
- [ ] 5-minute result cache TTL
- [ ] Microsoft 365 Admin Center deployment

### Phase 3: Analytical Gaps (~2 weeks)

**Cash Flow Statement (2–3 days)**
- [ ] `gold_cash_flow_indirect.sql` — derive from BS delta method
- [ ] Categories: Operating, Investing, Financing
- [ ] Account mapping seed: `cash_flow_categories.csv`
- [ ] Consolidated cash flow after FX translation
- [ ] Test: CF operating + investing + financing = net change in cash

**Multi-GAAP / Dual Reporting (1 week)**
- [ ] `reporting_standard` dimension (LOCAL_GAAP, IFRS)
- [ ] Per-standard consolidation adjustments
- [ ] Separate consolidated TB per standard

**Rolling Forecasts (2–3 days)**
- [ ] 12-month forward window, shifts monthly
- [ ] Actual for closed periods + forecast for open
- [ ] Scenario type `rolling`

### Phase 4: Budget Write-Back (~2 days)

- [ ] Budget Entry DocType with workflow: Draft → Submitted → Approved
- [ ] On Approve: write to `epm_staging.budget_input`
- [ ] `=EPM.SUBMIT()` from Excel to staging tables
- [ ] dbt picks up approved rows on next build

### Phase 5: Production Hardening (~3 days)

- [ ] ClickHouse backup automation
- [ ] Pipeline alerting on failure
- [ ] Monitoring: query latency + API response times
- [ ] Load testing: 50 concurrent Excel users
- [ ] Disaster recovery procedure

---

## Effort Summary

| Phase | Effort | Dependencies |
|-------|--------|-------------|
| Phase 1: Security & SSO | ~2 days | None |
| Phase 2: Excel Online | ~3 days | Phase 1 |
| Phase 3: Analytical gaps | ~2 weeks | None |
| Phase 4: Budget write-back | ~2 days | Phase 1 |
| Phase 5: Production hardening | ~3 days | Phase 1–2 |
| **Total** | **~4 weeks** | |
