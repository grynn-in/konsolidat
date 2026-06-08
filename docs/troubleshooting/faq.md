# FAQ

## Finance Users

**Q: How do I get started with EPM formulas in Excel?**
Follow the [Quickstart Guide](../getting-started/quickstart.md) — you'll have your first `=EPM()` value in 15 minutes.

**Q: What's the difference between EPM() and EPM_BUDGET()?**
`EPM_BUDGET()` is a shortcut for `EPM(..., "period_amount", "budget")`. See [Excel VBA Guide](../user-guide/excel-vba-guide.md) for all 5 functions.

**Q: Can I query quarterly or annual totals?**
Yes. Use period range codes: `"Q1"`, `"Q2"`, `"Q3"`, `"Q4"`, `"H1"`, `"H2"`, or `"FY"`. The API sums across the constituent months.

**Q: Why do all my cells show 0?**
Likely not refreshed. Press **Ctrl+Shift+R** to fetch values. If still 0, run `EPM_Debug` to test connectivity.

**Q: How do I filter by cost center or department?**
Add the optional parameters: `=EPM("USMF", 2024, 5, "401100", "period_net_amount", "actuals", "SALES", "SALES")`

**Q: How often is the data updated?**
After each Airbyte sync + dbt build cycle. Typically daily or on-demand. Ask your IT admin about the schedule.

**Q: Can I write budget data from Excel?**
Currently, budgets are managed via seed CSVs. A budget write-back feature (via staging tables) is on the roadmap.

**Q: What accounts are available?**
Your chart of accounts from D365. Use ClickHouse or ask your admin to query `SELECT DISTINCT main_account FROM epm_gold.gold_trial_balance`.

**Q: Can I use EPM() in Excel Online?**
The VBA module works only in desktop Excel. For Excel Online, the Office.js task pane add-in provides pipeline control, but custom formula functions are on the roadmap.

## IT Administrators

**Q: What are the hardware requirements?**
Minimum: 4 vCPU, 8 GB RAM for ClickHouse + Frappe combined. See [Deployment Guide](../admin-guide/deployment-guide.md) for sizing by workload.

**Q: How do I back up the system?**
ClickHouse data volumes + Frappe `bench backup`. See [Operations Runbook](../admin-guide/operations-runbook.md).

**Q: How do I add a new legal entity?**
1. Ensure the entity exists in D365
2. Run an Airbyte sync to pull its data
3. Add it to `consolidation_groups.csv` if it should be consolidated
4. Add it to `entity_fiscal_calendars.csv`
5. Run `dbt seed && dbt build`

**Q: How do I change the consolidation group structure?**
Edit `seeds/consolidation_groups.csv`, then `dbt seed && dbt build`.

**Q: How do I update exchange rates?**
Exchange rates come from D365 via Airbyte. Run a sync to pull the latest rates. The `silver_exchange_rates` model normalizes them (D365 stores rates × 100).

**Q: Can I use ClickHouse Cloud instead of self-hosted?**
Yes. Update the EPM Settings in Frappe with the cloud hostname, port, and credentials. See [Deployment Guide](../admin-guide/deployment-guide.md).

**Q: How do I monitor system health?**
- Frappe: `GET /api/method/konsol.api.health`
- ClickHouse: `docker inspect --format='{{.State.Health.Status}}' open_epm_clickhouse`
- See [Monitoring](../admin-guide/monitoring.md) for full setup.

**Q: How do I rotate the D365 client secret?**
1. Create a new secret in Azure AD
2. Update the Airbyte source configuration
3. Delete the old secret

## Developers

**Q: How do I add a new Gold model?**
See [Extending dbt Models](../developer-guide/extending-dbt-models.md) — create the SQL file, add YAML docs, write tests, build.

**Q: How does the dimension system work?**
Dimensions are defined once in `dbt_project.yml` and auto-propagated via Jinja macros. See [Adding Dimensions](../developer-guide/adding-dimensions.md).

**Q: How do I add a new API endpoint?**
Use `@frappe.whitelist()` in `konsol/api.py`. See [Extending the API](../developer-guide/extending-api.md).

**Q: Why use ClickHouse instead of PostgreSQL?**
ClickHouse is a columnar OLAP database optimized for aggregation queries. Financial reporting is almost entirely `SUM ... GROUP BY` — exactly what ClickHouse excels at. See ADR-001 in `docs/architecture.md`.

**Q: Can I run dbt against a different database?**
dbt-clickhouse is the only tested adapter. The SQL uses ClickHouse-specific functions (via `db_adapter.sql` macros), so other databases would require adapter changes.

**Q: How do I add a new allocation rule?**
Add a row to `allocation_rules.csv`, create driver data, and update the multi-step macro. See [Allocation Guide](../user-guide/allocation-guide.md).

**Q: How are tests structured?**
26 assertion tests in `dbt_project/tests/`. Each returns rows that violate a rule — zero rows = pass. See [Testing Guide](../developer-guide/testing-guide.md).

## Decision Makers

**Q: How does Open EPM compare to commercial CPM tools?**
See [Cost Comparison vs Commercial](../evaluation/cost-comparison-vs-commercial.md) — detailed 26-row feature parity matrix and 3-year TCO analysis.

**Q: What's the total cost of ownership?**
Estimated $20K–55K over 3 years vs $200K–$1.4M for commercial solutions. Main costs are infrastructure (~$200–400/mo) and internal FTE time.

**Q: What are the current gaps vs commercial tools?**
Cash flow statement, multi-GAAP support, and rolling forecasts. These are on the [Roadmap](../reference/roadmap.md).

**Q: What team do I need?**
2.5–3.5 FTE: Group Controller (1.0), FP&A Analyst (1–2), Data Engineer (1.0), IT Ops (0.2). See the cost comparison for details.

**Q: Is it production-ready?**
The core pipeline (D365 → ClickHouse → dbt → Frappe API → Excel) is functional with 60 models, 26 tests, and 3 API endpoints. Production hardening (HA, monitoring, audit trail) is in progress.
