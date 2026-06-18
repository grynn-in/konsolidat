# Setup Guide

## Prerequisites

- Docker Desktop (or Docker Engine + Compose)
- Python 3.10+
- Excel with Power Query (Microsoft 365 or Excel 2019+)
- PostgreSQL ODBC driver (for Excel → Cube connection)
- D365 Finance environment with OData API access

## Step 1: Clone and Configure

```bash
git clone https://github.com/pyy3/konsolidat.git
cd konsolidat
cp .env.example .env
```

Edit `.env` with your credentials:
- `CLICKHOUSE_PASSWORD` — change from default for production
- `D365_TENANT_ID`, `D365_CLIENT_ID`, `D365_CLIENT_SECRET` — Azure AD app registration
- `D365_ENVIRONMENT_URL` — your D365 F&O OData endpoint
- `CUBEJS_API_SECRET` — random string for Cube API security
- `CUBEJS_SQL_PASSWORD` — password for Excel ODBC connection

## Step 2: Start Infrastructure

```bash
docker compose up -d
```

Verify ClickHouse:
```bash
docker exec konsolidat_clickhouse clickhouse-client --password YOUR_PASSWORD --query "SHOW DATABASES"
```

You should see: `epm`, `epm_bronze`, `epm_silver`, `epm_gold`, `epm_staging`.

## Step 3: Install Airbyte

Airbyte runs as a **second stack** on the same server (via `abctl` / local Kubernetes),
connected to ClickHouse through a shared Docker network (`open_epm`).

```bash
bash scripts/setup-airbyte.sh
```

The script will:
1. Install `abctl` if not already present
2. Verify the Open EPM stack is running (the `open_epm` network must exist)
3. Run `abctl local install --network open_epm` to attach Airbyte to the shared network
4. Print the Airbyte UI URL and ClickHouse connection details

Access Airbyte UI at **http://localhost:8000** (default credentials: `airbyte` / `password`).

### Configure D365 Source

**Option A: Custom D365 connector** (recommended for full OData coverage)

1. In Airbyte UI → Settings → Custom Connectors → load from `source-d365-fno/`
2. Create a new Source using the custom connector
3. Enter your D365 OData URL: `https://your-env.operations.dynamics.com/data`
4. Auth: OAuth2 with Azure AD app registration (credentials from `.env`)

**Option B: Built-in connector**

1. In Airbyte UI, create a new Source → "Dynamics 365 Finance & Operations (OData)"
2. Enter your D365 OData URL: `https://your-env.operations.dynamics.com/data`
3. Auth: OAuth2 with Azure AD app registration

**Entities to sync** (15 total):
- `GeneralJournalAccountEntries`, `GeneralJournalEntries`
- `MainAccounts`, `MainAccountCategories`
- `LegalEntities`, `FiscalCalendars`, `FiscalCalendarYears`
- `FinancialDimensions`, `FinancialDimensionValues`
- `ExchangeRateCurrencyPairs`, `ExchangeRateTypes`
- `BudgetRegisterEntries`, `BudgetTransactionLines`
- `ConsolidationAccountGroups`
- `LedgerTrialBalanceFiscalYearSnapshotDataEntity`

Set `cross_company=true` for all entities.

### Configure ClickHouse Destination

1. Create Destination → ClickHouse
2. Host: **`konsolidat_clickhouse`** (container name on the shared `open_epm` network)
3. HTTP Port: **8123**
4. Database: **`epm_raw`**
5. Username/Password: from your `.env` (`CLICKHOUSE_USER` / `CLICKHOUSE_PASSWORD`)

> **Note:** Because Airbyte runs on the same Docker network as Open EPM, use the
> container name `konsolidat_clickhouse` — not `host.docker.internal` or `localhost`.

### Create Connection

1. Create Connection: D365 Source → ClickHouse Destination
2. Schedule: every 6 hours (or as needed)
3. Sync mode: Full Refresh | Overwrite (for initial load)
4. Run initial sync

### Webhook (optional)

Configure Airbyte to call the sync-complete webhook so Frappe can track sync status:
1. In Frappe → EPM Settings → set Airbyte API URL, Connection ID, and Webhook Secret
2. Airbyte will POST to `/api/method/konsol.api.airbyte_sync_complete` on sync completion

## Step 4: Run dbt

```bash
cd dbt_project
pip install dbt-core dbt-clickhouse
dbt deps
dbt seed    # Load allocation rules, consolidation groups, etc.
dbt build   # Build all models + run tests
```

## Step 5: Start Remaining Services

```bash
docker compose up -d
```

This starts:
- ClickHouse (analytics warehouse, ports 8123/9000)

## Step 6: Connect Excel

See [Excel User Guide](excel-user-guide.md) for detailed instructions.

Quick version:
1. Install PostgreSQL ODBC driver
2. In Excel: Data → Get Data → From ODBC
3. DSN: `host=localhost port=15432 dbname=epm_gold`
4. Username: `epm_excel` / Password: from `.env`
5. Select a view (e.g., `v_pnl_report`) → Load to PivotTable

## Step 7: D365 App Registration

In Azure Portal:

1. Register a new application
2. Add API permission: Dynamics 365 → `Ax.FullAccess`
3. Create a client secret
4. In D365: System Administration → Azure Active Directory → Register application
5. Enter the Client ID and assign appropriate security roles

The app needs read access to all 15 OData entities listed above.
