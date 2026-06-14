# PRDs — Index

*Last updated: 2026-06-13*

Per-feature Product Requirement Documents for the Konsolidat roadmap, grouped by roadmap phase. See [../reference/roadmap.md](../reference/roadmap.md) for the master plan.

## Phase 2 — Dynamic Schema (Dimensions, Measures & Facts)

| PRD | Summary | Status |
|---|---|---|
| [Fact Registry](PRD-FACT-REGISTRY.md) | Complete the `Fact Table` registry — grain, refresh frequency, required-artifact validation, pre-seeded facts, DDL + dbt source generation on save. | ✅ Implemented (konsol #14) |
| [API Generalisation](PRD-API-GENERALISATION.md) | Replace hardcoded dimension/measure params with generic `dimensions` dict + registry-validated `measure`/`fact`; backward-compatible `=EPM()`. | ✅ Implemented (konsol #14) |

## Phase 3 — Multi-ERP Support

| PRD | Summary | Status |
|---|---|---|
| [D365 Business Central Connector](PRD-D365-BC-CONNECTOR.md) | BC adapter via REST v2.0 / OData v4 (`generalLedgerEntries`) emitting canonical staging. | Not Started |
| [SAP S/4HANA Connector](PRD-SAP-S4HANA-CONNECTOR.md) | S/4HANA adapter via OData v4 CDS views (`I_JournalEntry`, `I_GLAccountLineItem`). | Not Started |
| [SAP ECC 6.0 Connector](PRD-SAP-ECC-CONNECTOR.md) | ECC adapter via RFC/BAPI or IDoc over BSEG + BKPF. | Not Started |
| [SAP Business One Connector](PRD-SAP-B1-CONNECTOR.md) | SAP B1 adapter via Service Layer REST (`JournalEntries` / JDT1). | Not Started |
| [ERPNext Connector](PRD-ERPNEXT-CONNECTOR.md) | ERPNext adapter via Frappe REST API over the `GL Entry` doctype. | ✅ Implemented (konsolidat #37) |
| [Dimension Harmonization](PRD-DIMENSION-HARMONIZATION.md) | Map per-ERP dimensions to canonical dimensions across connectors. | ✅ Implemented (konsolidat #38, konsol #18) |
| [Scale Architecture (50–500 LEs)](PRD-SCALE-ARCHITECTURE.md) | Incremental extraction, ClickHouse sharding, per-connector health for large multi-ERP estates. | Not Started |
| [Connector Registry (Frappe)](PRD-CONNECTOR-REGISTRY.md) | Frappe-driven catalog of connectors, credentials, and sync configuration. | ✅ Implemented (konsol #15) |

## Phase 4 — Security & SSO

| PRD | Summary | Status |
|---|---|---|
| [Security & Microsoft Entra ID SSO](PRD-SECURITY-ENTRA-SSO.md) | Entra ID OAuth2/OIDC login, group→role mapping, reverse-proxy TLS, ClickHouse network isolation. | Not Started |

## Phase 6 — Analytical Gaps & Enhancements

| PRD | Summary | Status |
|---|---|---|
| [Cash Flow Statement (Indirect Method)](PRD-CASH-FLOW-STATEMENT.md) | `gold_cash_flow_indirect` via balance-sheet delta method, Operating/Investing/Financing categories. | Not Started |
| [Multi-GAAP / Dual Reporting](PRD-MULTI-GAAP.md) | `reporting_standard` dimension with per-standard adjustment rules and independently balancing outputs. | Not Started |
| [Rolling Forecasts](PRD-ROLLING-FORECASTS.md) | 12-month forward window mixing actuals for closed periods and forecast for open; `rolling` scenario type. | Not Started |
| [Budget Cell Locking (Concurrency Control)](PRD-BUDGET-CELL-LOCKING.md) | Optimistic `modified`-timestamp checks on cell save, conflict responses, optional pessimistic locks. | Not Started |
| [Multi-Step Budget Approval Chain](PRD-BUDGET-APPROVAL-CHAIN.md) | Extended budget workflow (Draft→Dept→Controller→CFO) with role-gated transitions and notifications. | Not Started |
| [Consolidation Enhancements](PRD-CONSOLIDATION-ENHANCEMENTS.md) | Temporal equity rates, goodwill CTA, disposal recycling, NCI in business combinations, ownership changes. | Not Started |
| [Allocation Enhancements (Circular & Reciprocal)](PRD-ALLOCATION-ENHANCEMENTS.md) | Iterative convergence and simultaneous-equations methods for reciprocal cost pools. | Not Started |
| [Planning Enhancements (Driver-Based & Recurring)](PRD-PLANNING-ENHANCEMENTS.md) | Driver-based planning, phasing templates, recurring topside journals with approval. | Not Started |
| [Reporting Enhancements (Waterfall, Trend, Commentary)](PRD-REPORTING-ENHANCEMENTS.md) | Waterfall/bridge variance decomposition, trend analysis, commentary on variance cells. | Not Started |

## Phase 7 — Production Hardening

| PRD | Summary | Status |
|---|---|---|
| [Production Hardening](PRD-PRODUCTION-HARDENING.md) | Backup automation, monitoring/alerting, load testing, close runbook, disaster recovery. | Not Started |

## Governance

| PRD | Summary | Status |
|---|---|---|
| [Pipeline Build Governance](PRD-BUILD-GOVERNANCE.md) | Governed, tag-aware, approval-gated dbt builds via Pipeline Build Request + Airbyte sync preflight. | ✅ Implemented (konsol #16) |
