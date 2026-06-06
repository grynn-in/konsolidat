# Konsol vs. Commercial CPM: Cost & Feature Comparison

*Last updated: 2026-06-06*

## Overview

This document compares Konsol against the top 5 commercial Corporate Performance Management (CPM) platforms: CCH Tagetik (Wolters Kluwer), OneStream, Anaplan, Planful, and Prophix.

**Target market:** Private mid-market companies (2–50 entities) running D365 F&O. Konsol is not positioned for publicly listed companies requiring SOX certification or statutory regulatory reporting.

---

## Feature Parity Matrix

| Feature | **Tagetik** | **OneStream** | **Anaplan** | **Planful** | **Prophix** | **Konsol** |
|---|---|---|---|---|---|---|
| Multi-entity consolidation | Native | Native | Add-on | Native | Native | **Yes** (dbt gold layer) |
| FX translation (closing/avg rate) | Native | Native | Manual | Native | Native | **Yes** (IFRS/GAAP compliant) |
| CTA (equity plug) | Native | Native | Manual | Native | Native | **Yes** (PRD-2, tested) |
| IC elimination | Native | Native | Manual | Native | Native | **Yes** (3 rules, nets to zero) |
| Minority interest / NCI | Native | Native | Manual | Native | Native | **Yes** (ownership %, NCI columns) |
| Top-side adjustments | Native | Native | Yes | Yes | Yes | **Yes** (CSV-driven) |
| Multi-step allocations | Native | Native | Best-in-class | Yes | Yes | **Yes** (3-step cascade, driver-based) |
| Budget write-back | Native | Native | Native | Native | Native | **Yes** (FastAPI → ClickHouse staging) |
| Scenario management | Native | Native | Best-in-class | Yes | Yes | **Yes** (budget/forecast/what-if via API) |
| Variance analysis | Native | Native | Native | Native | Native | **Yes** (favorable logic, actual vs budget) |
| Budget spreading | Native | Native | Native | Native | Native | **Yes** (annual → monthly profiles) |
| Excel-native UI | Plugin | Plugin | No (web) | No (web) | Plugin | **Yes** (ODBC PivotTables + VBA) |
| Regulatory reporting | Strong | Growing | Weak | Moderate | Moderate | N/A (not targeted) |
| ESG reporting | Yes | Yes | No | No | No | N/A (not targeted) |
| Workflow/approvals | Native | Native | Native | Native | Native | **No** (roadmap) |
| Audit trail | Certified (SOX) | Certified (SOX) | Certified (SOX) | Certified (SOX) | Certified (SOX) | **Column-level** (sufficient for private companies) |
| User-facing web UI | Full | Full | Full | Full | Full | **Admin only** (Streamlit) |
| D365 F&O integration | Connector | Connector | Via API | Via API | Via API | **Native** (Airbyte OData) |
| Data quality tests | Internal | Internal | Internal | Internal | Internal | **21 dbt tests** |

---

## Cost Comparison (3-Year TCO, ~50 Users)

| Cost Item | **Tagetik** | **OneStream** | **Anaplan** | **Planful** | **Prophix** | **Konsol** |
|---|---|---|---|---|---|---|
| Year 1 license | $50K–100K | $80K–178K | $180K–350K | $240K | $170K–210K | **$0** |
| Year 2 license | $50K–100K | $80K–178K | $180K–350K | $240K | $170K–210K | **$0** |
| Year 3 license | $50K–100K | $80K–178K | $180K–350K | $240K | $170K–210K | **$0** |
| Implementation | $50K–200K | $50K–200K | $150K–350K | ~$100K | ~$80K | **$10K–30K** (internal) |
| Infra (hosting) | Included | Included | Included | Included | Included | **$3K–8K/yr** (VM + ClickHouse) |
| **3-Year Total** | **$200K–500K** | **$300K–700K** | **$700K–1.4M** | **$820K** | **$600K** | **$20K–55K** |
| **Savings vs. Konsol** | — | — | — | — | — | **90–97%** |

### Commercial Pricing Sources

- **CCH Tagetik**: ~$50K+/yr license, $10K–50K+ implementation ([PricingNow](https://pricingnow.com/question/tagetik-4-0-accounting-software-cost/))
- **OneStream**: ~$50K–178K/yr avg, $50K–200K implementation ([ITQlick](https://www.itqlick.com/onestream-xf/pricing), [Dokka](https://dokka.com/onestream-pricing/))
- **Anaplan**: ~$150K–350K/yr enterprise, implementation can equal Year 1 ([CheckThat.ai](https://checkthat.ai/brands/anaplan/pricing))
- **Planful**: ~$240K/yr for 100 users, ~$800K 3-year TCO ([ITQlick](https://www.itqlick.com/planful/competitors))
- **Prophix**: ~$170K–210K/yr, ~$600K 3-year TCO ([ITQlick](https://www.itqlick.com/planful/competitors))

---

## What Konsol Actually Ships

### Data Pipeline (Medallion Architecture)

| Layer | Models | Description |
|---|---|---|
| Bronze | 16 | Raw D365 OData extracts (GL, TB, budget, FX rates, dimensions, legal entities) |
| Silver | 8 | Standardized GL entries, trial balance, exchange rates, fiscal periods, accounts |
| Gold | 13 | Consolidated TB, IC elimination, CTA, allocations, variance, scenarios, P&L, BS |

### Consolidation Engine (Gold Layer)

- **`gold_consolidated_trial_balance`** — Multi-entity with closing rate (BS) and average rate (P&L)
- **`gold_ic_eliminations`** — Debit/credit matching across entities, conservative min-balance netting
- **`gold_fx_revaluation`** — CTA equity plug: `PnL × (closing - average) × ownership%`
- **`gold_fully_consolidated_tb`** — Union of entity balances + IC eliminations + CTA + topside adjustments
- **`gold_allocation_results`** — 3-step cascading allocations (IT/headcount → Facility/sqm → Mgmt/revenue)

### Write-Back API (FastAPI)

| Endpoint | Method | Purpose |
|---|---|---|
| `/api/v1/budget` | POST | Insert budget lines (batch) to staging |
| `/api/v1/budget/{scenario_id}` | GET | Read back budget for validation |
| `/api/v1/scenarios` | GET/POST | List or create scenarios (budget/forecast/whatif) |
| `/api/v1/assumptions` | POST | Insert planning assumptions |
| `/api/v1/excel/{table}` | GET | Return gold-layer data as JSON |
| `/api/v1/excel/{table}/csv` | GET | Return gold-layer data as CSV |
| `/api/v1/epm/batch` | POST | Batch cell retrieval (SmartView-style) |
| `/api/v1/epm/value` | GET | Single cell value lookup |
| `/api/v1/epm/members` | GET | Dimension members for dropdowns |

### Supporting Infrastructure

| Component | Purpose | Port |
|---|---|---|
| ClickHouse | Columnar analytical warehouse | 8123 (HTTP), 9000 (native) |
| Cube | Semantic layer + SQL API (Postgres wire protocol) | 4000 (API), 15432 (SQL) |
| Dagster | Orchestration (Airbyte → dbt asset graph) | 3000 |
| Streamlit | Admin UI (pipeline status, data quality, allocation rules, scenarios) | 8501 |
| Airbyte | D365 OData extraction | 8000 |

### Test Coverage

21 dbt validation tests covering:
- FX translation correctness (BS uses closing, P&L uses average)
- IC elimination nets to zero
- NCI + group = translated amount
- Each allocation step sums to pool
- CTA = zero for same-currency entities
- Variance formula correctness
- Trial balance balances
- Budget spread sums to annual total

---

## Real-World Gap Analysis: Private Luxury Retailer (e.g. multi-country, 7+ currencies, 70+ locations)

A company like a Swiss-headquartered luxury retailer with stores across CH, DE, AT, DK, FR, UK, and US illustrates what Konsol covers vs. what's still missing.

### Already Covered — No Gaps

| Requirement | Why It's Not a Gap |
|---|---|
| **Store-level P&L** | D365 financial dimensions (cost center, department, business unit) carry store/location on every GL entry. Konsol extracts these in bronze and flows them through to gold. Just configure the Cube schema to expose them. |
| **Management reporting hierarchies** (by region, brand, product category) | Same — financial dimensions support arbitrary rollups. Add hierarchy mapping as a dbt seed and join in gold models. |
| **Multi-currency consolidation** (CHF, EUR, GBP, DKK, USD) | Fully implemented — closing rate for BS, average rate for P&L, CTA equity plug, all tested. |
| **IC elimination** (intercompany sales between country entities) | Implemented with configurable rules (CSV seed). |
| **Budget vs actual by store/country** | gold_variance_analysis supports all dimensions from the GL. |

### Genuine Gaps (3 items)

| Gap | Impact | Why It Matters | Buildable? |
|---|---|---|---|
| **Cash flow statement** | High | CFOs need consolidated indirect cash flow. No CF model exists in dbt today. | Yes — derive from GL movements (BS delta method). ~2–3 days of dbt work. |
| **Multi-GAAP / dual reporting** | Medium | Swiss GAAP FER for local statutory + IFRS for group reporting. Konsol runs one consolidation path. | Yes — add a `reporting_standard` dimension to gold models and maintain two sets of adjustment rules. ~1 week. |
| **Rolling forecasts** | Medium | Retail needs 12-month rolling forecasts updated monthly, not just annual budget vs actual. | Yes — extend scenario management with a rolling window function and period-shift logic. ~2–3 days. |

### Not Gaps (commonly assumed, but wrong)

| Assumed Gap | Why It's Wrong |
|---|---|
| "No store/location dimension" | D365 GL entries carry financial dimensions — store, cost center, department are already in the data |
| "No inventory valuation" | GL has inventory accounts with correct balances; item-level costing stays in D365 (where it belongs) |
| "No headcount planning" | Nice-to-have, not a CPM blocker — most mid-market companies do this in Excel anyway |
| "No IFRS 16 lease accounting" | Stays in D365 or a dedicated lease module; not a consolidation tool's job |

---

## Current Limitations

| Gap | Impact | Workaround |
|---|---|---|
| **No cash flow statement** | High — CFOs need consolidated CF | Buildable: BS delta method in dbt (~2–3 days) |
| **No multi-GAAP** | Medium — one consolidation path only | Buildable: reporting_standard dimension (~1 week) |
| **No rolling forecasts** | Medium — annual scenarios only | Buildable: rolling window logic (~2–3 days) |
| **No workflow/approvals** | Medium — no budget sign-off chain | Email/Teams-based process; on roadmap |
| **No web UI for end users** | Medium — Excel-only for finance users | Streamlit admin exists; could extend |
| **Allocation rules in CSV** | Low — works but not click-to-edit | Streamlit page exists for editing |
| **No real-time GL sync** | Low — batch is fine for most EPM | Airbyte schedule (hourly possible) |

---

## Maintenance & Org Model

### Who Maintains Konsol?

In a mid-market company ($100M–$1B revenue, 2–50 entities), Konsol is maintained by a small team — typically 2.5–3.5 FTE touching the system, of which only 1 is technical.

| Role | FTE | Team | Responsibilities |
|---|---|---|---|
| **Group Controller** | 1 | Finance | Owns consolidation rules, IC elimination logic, group reporting. Edits CSV seeds (consolidation groups, IC rules, ownership %). Runs Excel reports. |
| **FP&A Analyst** | 1–2 | Finance | Budget input via Excel write-back, variance analysis, scenario management. Power user of PivotTables via Cube SQL. |
| **Data/Analytics Engineer** | 1 | IT or Finance | Maintains dbt models, Dagster schedules, Airbyte connections, ClickHouse. Owns the `docker compose` stack. The "platform owner." |
| **IT Ops** | 0.2 | IT | VM/server, backups, monitoring. Minimal — it's Docker containers. |

### Where the Data Engineer Sits

| Org Model | Reports To | Pros | Cons |
|---|---|---|---|
| **Finance team** ("Finance Engineer") | CFO / Head of Controlling | Understands the business, fast iteration | May lack infra skills (Docker, SQL optimization) |
| **IT team** | CIO / IT Manager | Strong on infra, security, backups | Doesn't understand consolidation accounting |
| **Hybrid / Analytics team** | CFO with IT dotted line | Best of both worlds | Harder to hire — needs both dbt and accounting knowledge |

Most common in Swiss/DACH mid-market: the Group Controller hires a "Finance Data Analyst" or "FP&A Engineer" who knows SQL/dbt and sits in the finance team. IT provides the VM and backups.

### Ongoing Maintenance Effort

| Task | Frequency | Effort | Who |
|---|---|---|---|
| Monthly close (run pipeline, verify consolidation) | Monthly | 2–4 hours | Controller + data engineer |
| Budget cycle (collect inputs, load scenarios) | Quarterly | 1–2 days | FP&A + data engineer |
| Add new entity or change ownership % | Rare | 30 min (edit CSV seed) | Controller |
| Add/change IC elimination rules | Rare | 30 min (edit CSV seed) | Controller |
| dbt model changes (new report, new dimension) | Quarterly | 1–2 days | Data engineer |
| Infrastructure (updates, backups, monitoring) | Monthly | 2–3 hours | IT ops / data engineer |
| Airbyte connector maintenance (D365 API changes) | Rare | Half day | Data engineer |

**Annual maintenance cost estimate:** ~$30K–50K of allocated time (0.3 FTE data engineer + 0.1 FTE controller overhead). Compare to $150K–350K/yr in commercial license fees alone — before implementation partner retainers.

### Comparison: Commercial CPM Org Requirements

A company running Tagetik or OneStream at similar scale typically needs:

| Role | FTE | Why More? |
|---|---|---|
| EPM Admin / CoE Lead | 1 | Vendor-specific skills (Tagetik scripting, OneStream XF rules) |
| Implementation partner | 0.5 (retainer) | Upgrades, patches, custom reports — vendor lock-in |
| Same finance roles | 2–3 | Controller + FP&A still needed regardless |

**Total CPM cost with commercial:** $200K–400K/yr (license + partner + admin). With Konsol: **$30K–50K/yr** (data engineer time + hosting).

---

## Ideal Customer Profile

| Profile | Fit | Why |
|---|---|---|
| **Private mid-market, 2–10 entities** | **Best fit** | Saves $200K–600K over 3 years, covers all core CPM functions |
| **D365 F&O shop wanting fast EPM** | **Best fit** | Native OData integration, `docker compose up` and go |
| **Budget-conscious with internal dbt/analytics team** | **Best fit** | Stack (dbt + ClickHouse + Cube) is mainstream, maintainable, extensible |
| **Private group, 10–50 entities** | **Good fit** | Handles NCI and multi-currency; validate at scale during PoC |
| **Planning-heavy (500+ planners)** | Consider commercial | Konsol write-back is functional but basic vs. Anaplan |

---

## Bottom Line

Konsol implements the three features traditionally cited as having "no open-source solution": financial consolidation, intercompany elimination, and FX translation with CTA. For a private mid-market D365 F&O company, it replaces ~80% of what commercial CPM platforms deliver at 3–10% of the cost — saving $200K–600K over three years.
