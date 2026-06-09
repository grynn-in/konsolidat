# [konsolid.at](https://konsolid.at)

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

## Why Konsolidat?

- **Excel is the interface** — No new software to learn. One formula connects Excel to the analytical warehouse.
- **Transparent and auditable** — Every transformation is version-controlled SQL. 44 dbt models, 26 automated tests. The code is the documentation.
- **Open source** — MIT licensed. No vendor lock-in. Full access to every line of code.

## 3-Year Cost of Ownership (~50 users)

| Solution | 3-Year Total |
|---|---|
| Tagetik | $200,000 – $500,000 |
| OneStream | $300,000 – $700,000 |
| Anaplan | $700,000 – $1,400,000 |
| **Konsolidat** | **$20,000 – $55,000** |

## Built on Open Source Stack

<p align="center">
  <a href="https://clickhouse.com"><img src="https://img.shields.io/badge/ClickHouse-FADB14?style=for-the-badge&logo=clickhouse&logoColor=black" alt="ClickHouse"></a>
  <a href="https://airbyte.com"><img src="https://img.shields.io/badge/Airbyte-615EFF?style=for-the-badge&logo=airbyte&logoColor=white" alt="Airbyte"></a>
  <a href="https://getdbt.com"><img src="https://img.shields.io/badge/dbt-FF694A?style=for-the-badge&logo=dbt&logoColor=white" alt="dbt"></a>
  <a href="https://frappe.io"><img src="https://img.shields.io/badge/Frappe-0089FF?style=for-the-badge&logo=frappe&logoColor=white" alt="Frappe"></a>
  <a href="https://cube.dev"><img src="https://img.shields.io/badge/Cube.js-FF6492?style=for-the-badge&logo=cube&logoColor=white" alt="Cube.js"></a>
</p>

| | Technology | Role |
|---|---|---|
| ![](https://img.shields.io/badge/-FADB14?style=flat-square&logo=clickhouse&logoColor=black) | **ClickHouse** | Columnar analytics warehouse |
| ![](https://img.shields.io/badge/-615EFF?style=flat-square&logo=airbyte&logoColor=white) | **Airbyte** | ELT data integration |
| ![](https://img.shields.io/badge/-FF694A?style=flat-square&logo=dbt&logoColor=white) | **dbt Core** | SQL transformations (Medallion Architecture) |
| ![](https://img.shields.io/badge/-0089FF?style=flat-square&logo=frappe&logoColor=white) | **Frappe** | Web framework, API, auth, workflow |
| ![](https://img.shields.io/badge/-FF6492?style=flat-square&logo=cube&logoColor=white) | **Cube.js** | Semantic layer for metrics and dimensions |

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
