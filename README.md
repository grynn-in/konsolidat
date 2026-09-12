# [konsolid.at](https://konsolid.at)

Open-source Enterprise Performance Management. Multi-entity consolidation, Excel-native budgeting, driver-based allocations, and variance analysis — powered by `=K.EPM()` in the spreadsheet your finance team already knows.

**90% cheaper than commercial EPM/CPM tools. MIT Licensed.**

## What It Does

- **IFRS Consolidation** — Foreign exchange translation, intercompany elimination, non-controlling interest, cumulative translation adjustments
- **Cost Allocations** — Multi-step cascading engine with headcount, area, and revenue drivers
- **Budgeting & Variance** — Layered budgets with seasonal spreads, actual vs budget with favorable logic
- **Excel-Native Reporting** — Seven `K.` worksheet functions (`=K.EPM()` and the rest) query the analytical warehouse directly and write budgets back

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
./deploy.sh
```

`./deploy.sh` generates `.env` with random secrets if it is missing, starts
the infrastructure, stages the konsol app in `docker/frappe/konsol`, builds
the Frappe image, runs the configurator (site setup plus `bench migrate`),
starts the application and runs the dbt build, in that order.

To do the same by hand, run these steps in this order. They assume `.env`
has real secrets and the konsol app is staged:

```bash
docker compose up -d mariadb redis_cache redis_queue clickhouse
docker compose build frappe_backend                    # the one Frappe image
docker compose --profile setup run --rm configurator   # site setup + bench migrate
docker compose up -d
docker compose --profile setup run --rm dbt_init       # dbt build
```

> **Build, then migrate, then run dbt.** Only `frappe_backend` builds the
> shared Frappe image. Build it before running the configurator: the
> configurator can't build it, and its project doesn't include
> `frappe_backend`, so on a fresh host it fails with "No such image".
> A plain `docker compose up -d` does not run the configurator, because it is
> in the `setup` profile.
>
> Since konsolidat#146 this project has no seeds. Every reference table
> (currencies, the consolidation structure, dimension mappings, spread
> profiles, fiscal calendars, budget input) is written by the konsol Frappe
> app. Running dbt against a fresh ClickHouse before konsol has migrated gives
> you empty reference tables and models that build against nothing, with no
> seed left to fall back on.

## Documentation

Full docs, guides, and API reference at **[konsolid.at](https://konsolid.at)**

## License

MIT
