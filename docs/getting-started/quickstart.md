# Quickstart: Zero to First =K.EPM() Value in 15 Minutes

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

## Step 4: Install the Excel add-in (3 min)

1. Take `konsol/public/excel-addin/manifest.xml` from the konsol repository. It points at the demo server, `https://demo.konsolidat.com`: replace every occurrence with your Frappe URL (e.g. `http://localhost:8069`), because the worksheet functions call the server the add-in was loaded from
2. In Excel, use **Upload My Add-in** (under **My Add-ins**) and select the manifest
3. The **Konsolidat** button appears on the Home tab

## Step 5: Connect and Query (2 min)

1. Open the **Konsolidat** task pane and sign in with your Frappe username and password
2. In any cell, type:

```
=K.EPM("USMF", 2024, 5, "401100")
```

You should see the net amount for entity USMF, fiscal year 2024, period 5, account 401100.

## What Just Happened?

```
Excel cell → K.EPM() → add-in batch POST → Frappe API → ClickHouse query → value returned
```

The add-in:
1. Grouped the `K.` calls Excel made
2. Sent them in as few POSTs as possible to `/api/method/konsol.api.epm_batch`
3. Returned each value to its cell

## Next Steps

- [Excel Formulas Guide](../user-guide/excel-formulas-guide.md) — All formula functions, period ranges, building reports
- [Setup Guide](setup-guide.md) — Full deployment with D365 data extraction
- [Configuration Reference](configuration-reference.md) — All settings explained
- [Report Catalog](../user-guide/report-catalog.md) — Pre-built report patterns
