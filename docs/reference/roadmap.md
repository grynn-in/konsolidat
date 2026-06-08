# Open EPM — Roadmap

*Last updated: 2026-06-08*

## Status Summary

| Area | Status |
|------|--------|
| Data pipeline (Bronze → Silver → Gold) | **Done** — 44 dbt models, 26 tests, 11 seeds |
| Consolidation (FX, IC elim, CTA, NCI) | **Done** — IFRS/GAAP compliant, fully tested |
| Allocations (multi-step cascade) | **Done** — 3-step with headcount/sqm/revenue drivers |
| Budgeting & spreading | **Done** — Annual input, configurable profiles, 12-period spread |
| Budget layers (collaborative) | **Done** — 4 additive layers (base/challenge/management/board) |
| Budget write-back from Excel | **Done** — EPMSAVE() immediate write, EPM_BUDGET_SAVE macro |
| Variance analysis | **Done** — Actual vs budget with favorable logic, YTD, quarterly |
| Scenario management | **Done** — Actuals/budget/forecast/whatif, scenario_id filter |
| Excel VBA integration | **Done** — 6 functions (EPM, EPM_BUDGET, EPM_VARIANCE, EPM_DEBIT, EPM_CREDIT, EPMSAVE), 7 macros, batch API, period ranges |
| Frappe API (Konsol) | **Done** — 6 endpoints (health, epm_value, epm_batch, budget_save, budget_save_batch, budget_cell_save) |
| Frappe EPM Module | **Done** — 12 doctypes, budget workflow, 4 roles, 158 tests |
| Frappe EPM Settings | **Done** — ClickHouse, Airbyte, dbt config |
| Excel Task Pane (pipeline control) | **Done** — Office.js add-in, login, trigger, status |
| Prior year comparison | **Done** — YoY variance model |
| BS movement schedule | **Done** — Opening/movement/closing model |
| Documentation | **Done** — 31-file doc suite + budget layers guide |
| D365 budget write-back | Not started |
| Entra ID SSO | Not started |
| Excel Online custom functions | Not started |
| Cash flow statement | Not started |
| Multi-GAAP | Not started |
| Rolling forecasts | Not started |

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
- Budget layers: base + challenge + management + board (additive, role-flexible)
- Actual vs budget variance with favorable/unfavorable logic
- YTD running totals (trial balance and consolidated)
- Quarterly and half-yearly aggregations
- Prior year comparison with YoY variance
- Balance sheet movement schedule

### Frappe / Konsol App ([grynn-in/konsol](https://github.com/grynn-in/konsol))
- EPM module: 12 doctypes (Scenario Definition, Dimension, Measure, Fiscal Period, Spread Profile, Allocation Rule, Allocation Driver, Consolidation Group, IC Elimination Rule, Consolidation Adjustment, Budget Input, Budget Input Child)
- Budget workflow: Draft → Submitted → Approved → Rejected (4 roles)
- ClickHouse sync: on_update hooks → TRUNCATE + INSERT
- dbt config regeneration: Dimension/Measure/Fiscal Period doctypes → dbt_project.yml vars
- API: epm_value, epm_batch (read), budget_save, budget_save_batch, budget_cell_save (write)
- scenario_id optional filter for multi-scenario queries
- 166 TDD tests across 10 test files

### Excel Integration
- VBA module: EPM, EPM_BUDGET, EPM_VARIANCE, EPM_DEBIT, EPM_CREDIT (read)
- EPMSAVE: immediate write-back per cell (skips unchanged values)
- EPM_BUDGET_SAVE: batch macro for budget template sheets
- Batch refresh: Ctrl+Shift+R (all EPM cells in one HTTP round-trip)
- Period ranges: Q1–Q4, H1/H2, FY
- Office.js task pane for pipeline orchestration

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

### Phase 3: D365 Budget Write-Back (~1 day)

Push approved budgets from Open EPM back into D365 F&O so that D365's native budget control (encumbrance checking, PO validation) works with Open EPM budgets.

**Flow:**

```
Open EPM                              D365 F&O
────────                              ────────

Budget Input (Approved)
  ↓ on_update hook
  ├──→ ClickHouse sync (existing)
  └──→ D365 OData POST (new)
         ↓
       Budget Register Entry
         ↓
       Budget Control (encumbrance)
       PO validation against budget
       D365 native budget reports
```

**Implementation:**

- [ ] New module: `konsol/d365_writeback.py`
    - On Budget Input approval → POST to D365 OData API
    - Create `BudgetRegisterEntryHeader` (journal number, budget model, date)
    - Create `BudgetRegisterEntryLines` (one per period — account, amount, financial dimensions)
- [ ] Dimension mapping: translate `dim_cost_center = "SALES"` → D365 `DefaultDimension` format (dimension set with `CostCenter=SALES, Department=SALES`)
- [ ] Budget Model mapping: map `scenario_id = "BUDGET_2025"` → D365 Budget Model (e.g., `"OPENEPM"`)
- [ ] Idempotency: store D365 journal number on Budget Input doc — don't double-post on retry
- [ ] EPM Settings fields: D365 write-back URL, Budget Model name, enable/disable toggle

**Prerequisites:**

| Item | How |
|------|-----|
| OAuth app registration | Already exists (Airbyte uses it for reading D365) |
| Write permission on Budget entities | Enable `BudgetRegisterEntryHeaders` and `BudgetRegisterEntryLines` data entities for the app registration in D365 |
| Budget Model in D365 | Create a Budget Model (e.g., `"OPENEPM"`) in D365: Budgeting → Setup → Budget models |
| Financial Dimension mapping | Configure in EPM Settings: map Open EPM dimension names to D365 financial dimension names |

**D365 OData endpoints:**

```
POST https://{d365-url}/data/BudgetRegisterEntryHeaders
{
  "EntryNumber": "OPENEPM-BUDGET_2025-6100",
  "BudgetModelId": "OPENEPM",
  "BudgetTransactionType": "Original",
  "DefaultLedgerDimensionDisplayValue": "6100-SALES-SALES"
}

POST https://{d365-url}/data/BudgetRegisterEntryLines
{
  "EntryNumber": "OPENEPM-BUDGET_2025-6100",
  "Date": "2025-01-01",
  "AccountStructure": "Manufacturing P&L",
  "LedgerDimensionDisplayValue": "6100-SALES-SALES",
  "TransactionCurrencyAmount": 95000
}
```

**When to build:** Only needed if D365 budget control (encumbrance checking on POs, budget validation on journals) must reflect Open EPM budgets. If budgets are only consumed in Excel reports, this is unnecessary.

### Phase 4: Analytical Gaps (~2 weeks)

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
| Phase 3: D365 Budget Write-Back | ~1 day | Phase 1, D365 admin config |
| Phase 4: Analytical gaps | ~2 weeks | None |
| Phase 5: Production hardening | ~3 days | Phase 1–2 |
| **Total** | **~4 weeks** | |
