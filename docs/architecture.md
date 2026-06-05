# Open EPM Architecture

## Overview

Open EPM is an open-source Enterprise Performance Management stack for D365 Finance. It provides Excel-native budgeting, consolidation, and reporting at a fraction of the cost of commercial EPM tools.

## Data Flow

```
┌──────────────┐     ┌──────────┐     ┌────────────┐     ┌──────────┐     ┌───────┐
│  D365 F&O    │────▶│ Airbyte  │────▶│ ClickHouse │────▶│  Cube    │────▶│ Excel │
│  (OData)     │     │ (abctl)  │     │ (warehouse)│     │ (SQL API)│     │       │
└──────────────┘     └──────────┘     └────────────┘     └──────────┘     └───────┘
                                           │                                  │
                                      ┌────┴────┐                       ┌────┴────┐
                                      │   dbt   │                       │ FastAPI │
                                      │  Core   │                       │(write-  │
                                      │         │                       │  back)  │
                                      └─────────┘                       └─────────┘
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
| Write-back | FastAPI | Budget/forecast input from Excel |
| Admin UI | Streamlit | Pipeline monitoring, rule editing |
| User UI | Excel | PivotTables via ODBC to Cube SQL API |

## Key Design Decisions

### ADR-001: ClickHouse over PostgreSQL
ClickHouse provides 10-100x faster aggregation queries for TB/consolidation workloads. MergeTree family engines (SummingMergeTree for TB) match EPM access patterns perfectly.

### ADR-002: Airbyte via abctl, not Docker Compose
Airbyte is resource-heavy and has its own orchestration. Running it via `abctl` (local K8s) keeps Docker Compose lean. Dagster talks to Airbyte API on `localhost:8000`.

### ADR-003: Cube SQL API for Excel
Excel connects via PostgreSQL ODBC driver to Cube's SQL API (port 15432). This avoids REST API complexity and gives Excel users native PivotTable support. Cube handles caching and query optimization.

### ADR-004: Write-back via FastAPI + Staging
Budget/forecast input goes to ClickHouse staging tables, not back to D365. dbt unions staging data with actuals in the next run. This keeps D365 as the read-only source of truth.

### ADR-005: Seed-driven Allocations
Allocation rules and drivers are CSV seeds editable in Streamlit. This gives finance users self-service control without requiring SQL knowledge.

## Security

- Cube SQL API uses username/password auth (configurable in `.env`)
- FastAPI should be placed behind an auth proxy in production
- ClickHouse password should be changed from default for production
- D365 OData uses Azure AD app registration (client credentials flow)
