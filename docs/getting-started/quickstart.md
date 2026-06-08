# Quickstart: Zero to First =EPM() Value in 15 Minutes

Get Konsolidat running locally and pull your first financial value into Excel.

## Prerequisites

- Docker Desktop (or Docker Engine + Compose)
- Python 3.10+ with `pip`
- Excel (desktop, Windows or Mac)
- Frappe Bench installed ([bench docs](https://frappeframework.com/docs/user/en/installation))

## Step 1: Start ClickHouse (2 min)

```bash
cd konsolidat
cp .env.example .env          # Review defaults: CLICKHOUSE_PASSWORD=konsolidat_dev
docker compose up -d
```

Verify:

```bash
docker exec konsolidat_clickhouse clickhouse-client --query "SELECT 1"
# Should print: 1
```

## Step 2: Run dbt (3 min)

```bash
cd dbt_project
pip install dbt-core dbt-clickhouse    # If not already installed
dbt deps                                # Install packages
dbt seed                                # Load reference data (11 CSV seeds)
dbt build                               # Build all 44 models + run 26 tests
```

On success you'll see `Completed successfully. Done.` with 0 errors.

## Step 3: Set Up Frappe/Konsol (5 min)

If you haven't already set up a Frappe bench with the Konsol app:

```bash
cd ~/frappe-bench
bench start    # Starts Frappe on http://localhost:8069
```

Configure EPM Settings in Frappe Desk:

1. Go to **Setup → EPM Settings**
2. Set ClickHouse Host = `localhost`, Port = `8123`, User = `default`, Password = your `.env` password
3. Save

## Step 4: Import VBA into Excel (3 min)

1. Open a new Excel workbook
2. Press **Alt+F11** to open the VBA Editor
3. **File → Import File** → select `excel/OpenEPM.bas`
4. Close the VBA Editor
5. Save as `.xlsm` (macro-enabled workbook)

## Step 5: Connect and Query (2 min)

1. In Excel, run **EPM_SetServer** from the macro menu (Alt+F8)
   - Enter: `http://localhost:8069`
2. Run **EPM_Login** — enter your Frappe username and password
3. In any cell, type:

```
=EPM("USMF", 2024, 5, "401100")
```

4. Press **Ctrl+Shift+R** to refresh

You should see the net amount for entity USMF, fiscal year 2024, period 5, account 401100.

## What Just Happened?

```
Excel cell → EPM() function → VBA batch POST → Frappe API → ClickHouse query → value returned
```

The VBA module:
1. Scanned your sheet for all `EPM()`-family formulas
2. Batched them into a single POST to `/api/method/konsol.api.epm_batch`
3. Cached the results and triggered a recalculation

## Next Steps

- [Excel VBA Guide](../user-guide/excel-vba-guide.md) — All 5 formula functions, period ranges, building reports
- [Setup Guide](setup-guide.md) — Full deployment with D365 data extraction
- [Configuration Reference](configuration-reference.md) — All settings explained
- [Report Catalog](../user-guide/report-catalog.md) — Pre-built report patterns
