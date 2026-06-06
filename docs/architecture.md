# Open EPM Architecture

## Overview

Open EPM is an open-source Enterprise Performance Management stack for D365 Finance. It provides Excel-native budgeting, consolidation, and reporting at a fraction of the cost of commercial EPM tools.

## Data Flow (Target Architecture)

```
┌──────────────────────────────────────────────────────────┐
│  Users                                                    │
│  ┌──────────┐  ┌──────────────┐  ┌────────────────────┐  │
│  │ Excel    │  │ Excel Online │  │ Frappe Desk        │  │
│  │ Desktop  │  │ / iPad       │  │ (Web UI)           │  │
│  │ (ODBC)   │  │ (Add-in)     │  │                    │  │
│  └────┬─────┘  └──────┬───────┘  └───────┬────────────┘  │
└───────┼───────────────┼──────────────────┼────────────────┘
        │               │                  │
        │          HTTPS + Entra SSO       │
        ▼               ▼                  ▼
┌──────────────────────────────────────────────────────────┐
│  Frappe (Application Layer)                               │
│                                                           │
│  DocTypes: Budget Entry, Scenario, Consolidation Group,   │
│            IC Elimination Rule, Allocation Rule           │
│                                                           │
│  Built-in: Auth, RBAC, Workflows, Audit, REST API         │
│  DB: MariaDB (metadata + config only)                     │
└──────────────────┬───────────────────────────────────────┘
                   │ clickhouse-connect
                   ▼
┌──────────────────────────────────────────────────────────┐
│  ClickHouse (Azure / AWS — managed or self-hosted)        │
│                                                           │
│  epm_bronze  ← Airbyte (D365 OData)                      │
│  epm_silver  ← dbt (standardized)                        │
│  epm_gold    ← dbt (consolidated TB, IC elim, CTA)       │
│  epm_staging ← Frappe writes budget/config here           │
│                                                           │
│  Cube SQL API (port 15432) → Excel ODBC / Add-in         │
└──────────────────────────────────────────────────────────┘
```

### Current Data Flow (v1 — FastAPI)

```
D365 F&O (OData) → Airbyte → ClickHouse → dbt → Cube → Excel
                                                    ↑
                                              FastAPI (write-back)
```

## Medallion Architecture

| Layer | Database | Purpose |
|-------|----------|---------|
| Bronze | `epm_bronze` | Raw data from Airbyte, explicit type casting |
| Silver | `epm_silver` | Standardized, cleaned, D365 quirks handled |
| Gold | `epm_gold` | Business-ready: TB, P&L, BS, consolidation |
| Staging | `epm_staging` | Write-back from API (budget input) |

## Component Stack

| Component | Technology | Purpose |
|-----------|-----------|---------|
| Extraction | Airbyte (abctl) | D365 OData → ClickHouse |
| Warehouse | ClickHouse | Columnar analytics, fast aggregation |
| Transformation | dbt Core | Medallion layer models + tests |
| Semantic Layer | Cube Core | SQL API (Postgres wire) for Excel |
| Orchestration | Dagster | Airbyte + dbt asset graph, schedules |
| Write-back | FastAPI (v1) → Frappe (v2) | Budget/forecast input from Excel |
| Admin UI | Streamlit (v1) → Frappe Desk (v2) | Pipeline monitoring, rule editing, config management |
| User UI | Excel (Desktop + Online) | PivotTables via ODBC; `=EPM.VALUE()` via Add-in |
| Auth & RBAC | — (v1) → Frappe (v2) | Users, roles, SSO, 2FA, audit trail |
| Workflow | — (v1) → Frappe (v2) | Budget approval: Draft → Submitted → Approved |

## Key Design Decisions

### ADR-001: ClickHouse over PostgreSQL
ClickHouse provides 10-100x faster aggregation queries for TB/consolidation workloads. MergeTree family engines (SummingMergeTree for TB) match EPM access patterns perfectly.

### ADR-002: Airbyte via abctl, not Docker Compose
Airbyte is resource-heavy and has its own orchestration. Running it via `abctl` (local K8s) keeps Docker Compose lean. Dagster talks to Airbyte API on `localhost:8000`.

### ADR-003: Cube SQL API for Excel
Excel connects via PostgreSQL ODBC driver to Cube's SQL API (port 15432). This avoids REST API complexity and gives Excel users native PivotTable support. Cube handles caching and query optimization.

### ADR-004: Write-back via Staging (D365 stays read-only)
Budget/forecast input goes to ClickHouse staging tables, not back to D365. dbt unions staging data with actuals in the next run. This keeps D365 as the read-only source of truth.

### ADR-005: Seed-driven Allocations (v1) → Frappe DocTypes (v2)
v1: Allocation rules and drivers are CSV seeds editable in Streamlit.
v2: Rules move to Frappe DocTypes — web-editable, versioned, audited, role-protected. Frappe syncs config to ClickHouse on save, triggering a dbt rebuild.

### ADR-006: Frappe over FastAPI for Application Layer
FastAPI is minimal and fast but requires building auth, RBAC, audit, workflows, and web UI from scratch. Frappe provides all of these out of the box. Trade-off: heavier deployment (MariaDB + Redis + workers), but `docker compose` handles it. Frappe's DB (MariaDB) stores only metadata and config — all analytical data stays in ClickHouse.

### ADR-007: Excel Custom Functions Add-in for Online/Desktop/iPad
`=EPM.VALUE(entity, year, period, account, scenario)` replaces the Hyperion `HsGetValue()` pattern. Built as an Office Add-in (TypeScript + Office.js), authenticates via MSAL.js + Entra ID, and calls Frappe API endpoints. Works in Excel Online, Desktop, and iPad — unlike SmartView which is desktop-only.

## Security

See [`docs/security-architecture.md`](security-architecture.md) for the full security design.

**Summary:**
- **Identity:** Microsoft Entra ID (same tenant as D365) — SSO for all users
- **Auth:** Frappe validates JWT tokens; RBAC enforced on every DocType and API
- **Roles:** Reader (view) → Planner (view + submit budgets) → Controller (+ edit config) → Admin (+ user management)
- **Transport:** HTTPS via Caddy reverse proxy with auto-TLS; CORS for `*.officeapps.live.com`
- **Audit:** Frappe built-in — every change logged with user, timestamp, field-level diff
- **ClickHouse:** Never exposed to internet — private network only, accessed via Frappe or Cube
- **D365 OData:** Azure AD app registration (client credentials flow)

## Excel Online: EPM.VALUE() Custom Function

The Excel Add-in provides HSGETVALUE-equivalent cell formulas:

| Formula | Purpose |
|---|---|
| `=EPM.VALUE(entity, year, period, account, scenario, [cost_center], [dept])` | Single cell value |
| `=EPM.CONSOLIDATED(entity, year, period, account, measure)` | Consolidated group amount |
| `=EPM.VARIANCE(entity, year, period, account)` | Actual vs budget variance |
| `=EPM.MEMBERS(dimension)` | Populate dropdown lists |
| `=EPM.SUBMIT(range, scenario_id)` | Write budget data (planner role only) |

See [`docs/security-architecture.md`](security-architecture.md) for full add-in design, auth flow, and comparison to Hyperion SmartView.
