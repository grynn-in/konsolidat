# Konsolidat

Open-source CPM for D365 Finance. Multi-entity consolidation, Excel-native budgeting, and reporting — at 3% of the cost of Tagetik or OneStream.

## Architecture

```
D365 F&O (OData) → Airbyte → ClickHouse → dbt Core → Cube → Excel
                                                    ↑
                                              FastAPI (write-back)
```

**Medallion layers**: Bronze (raw) → Silver (standardized) → Gold (business-ready)

**Orchestration**: Dagster | **Admin UI**: Streamlit | **User UI**: Excel via Cube SQL API

## Quick Start

```bash
# 1. Clone and configure
git clone https://github.com/pyy3/open_epm.git
cd open_epm
cp .env.example .env
# Edit .env with your ClickHouse password and D365 credentials

# 2. Start infrastructure
docker compose up -d

# 3. Install Airbyte (runs separately via abctl)
# See docs/setup-guide.md

# 4. Run dbt
cd dbt_project
dbt deps
dbt build

# 5. Connect Excel
# See docs/excel-user-guide.md
```

## Components

| Component | Purpose | Port |
|-----------|---------|------|
| ClickHouse | Analytical warehouse | 8123 (HTTP), 9000 (native) |
| Cube | Semantic layer + SQL API | 4000 (API), 15432 (SQL) |
| Dagster | Orchestration | 3000 |
| FastAPI | Budget write-back | 8080 |
| Streamlit | Admin UI | 8501 |
| Airbyte | D365 extraction (via abctl) | 8000 |

## Features

- **Trial Balance**: Multi-entity, multi-currency trial balance from D365 GL
- **Consolidation**: Multi-company with IC elimination and currency translation
- **Budgeting**: Excel-native budget input with write-back API
- **Allocations**: Driver-based cost allocation engine
- **Scenarios**: Version-controlled budget/forecast/what-if scenarios
- **Reporting**: Excel PivotTables via Cube SQL API (Postgres wire protocol)

## Documentation

| Document | Description |
|----------|-------------|
| [Architecture](docs/architecture.md) | System design, ADRs, data flow, security overview |
| [Security Architecture](docs/security-architecture.md) | Frappe + Entra ID SSO, RBAC, Excel Online Add-in design |
| [Cost Comparison](docs/cost-comparison-vs-commercial.md) | Konsol vs. Tagetik, OneStream, Anaplan, Planful, Prophix |
| [Roadmap](docs/roadmap.md) | Remaining activities: Frappe migration, Excel Online, analytical gaps |
| [Setup Guide](docs/setup-guide.md) | Installation and configuration |
| [Consolidation Guide](docs/consolidation-guide.md) | Multi-entity consolidation, FX, IC elimination |
| [Allocation Guide](docs/allocation-guide.md) | Multi-step cascading allocations |
| [Excel User Guide](docs/excel-user-guide.md) | PivotTables, budget submission, ODBC setup |

## License

MIT
