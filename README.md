# Konsolidat

Open-source Enterprise Performance Management. Multi-entity consolidation, Excel-native budgeting, driver-based allocations, and variance analysis — powered by `=EPM()` in the spreadsheet your finance team already knows.

**90% cheaper than commercial CPM tools. MIT Licensed.**

## What It Does

- **IFRS Consolidation** — Foreign exchange translation, intercompany elimination, non-controlling interest, cumulative translation adjustments
- **Cost Allocations** — Multi-step cascading engine with headcount, area, and revenue drivers
- **Budgeting & Variance** — Layered budgets with seasonal spreads, actual vs budget with favorable logic
- **Excel-Native Reporting** — Five `=EPM()` worksheet functions query the analytical warehouse directly

## Architecture

```
ERP (D365 / SAP / ERPNext)
  → Airbyte (ELT)
    → ClickHouse (Columnar DW)
      → dbt Core (Medallion Architecture: Bronze → Silver → Gold)
        → Cube.js (Semantic Layer)
          → Frappe (API, Auth, Workflow)
            → Excel (=EPM formulas)
```

## Quick Start

```bash
cp .env.example .env
docker compose up -d
cd dbt_project && dbt deps && dbt seed && dbt build
```

## Documentation

Full docs, guides, and API reference at **[konsolid.at](https://konsolid.at)**

## License

MIT
