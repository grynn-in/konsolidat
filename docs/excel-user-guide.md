# Excel User Guide

## Connecting Excel to Konsolidat

Konsolidat exposes data through Cube's SQL API, which speaks PostgreSQL wire protocol. Excel connects via ODBC.

### Install PostgreSQL ODBC Driver

1. Download from https://www.postgresql.org/ftp/odbc/
2. Install the 64-bit Unicode driver
3. Restart Excel after installation

### Create ODBC Connection

**Option A: Power Query (Recommended)**

1. Excel → Data → Get Data → From Other Sources → From ODBC
2. Connection string: `Driver={PostgreSQL Unicode};Server=localhost;Port=15432;Database=epm_gold;Uid=epm_excel;Pwd=YOUR_PASSWORD`
3. Select a table/view → Load

**Option B: ODBC DSN**

1. Open ODBC Data Source Administrator (64-bit)
2. Add → PostgreSQL Unicode → Configure:
   - Data Source: `Konsolidat`
   - Server: `localhost`
   - Port: `15432`
   - Database: `epm_gold`
   - User: `epm_excel`
   - Password: from `.env`
3. Test → OK
4. In Excel: Data → Get Data → From ODBC → Select DSN

### Available Views

| View | Description | Key Dimensions |
|------|-------------|----------------|
| `v_pnl_report` | Profit & Loss by period | Entity, Year, Period, Account, Cost Center |
| `v_balance_sheet` | Balance Sheet | Entity, Year, Period, Account |
| `v_budget_vs_actual` | Budget vs Actual comparison | Entity, Year, Period, Account, Scenario |
| `v_consolidated_report` | Group consolidated report | Group, Entity, Year, Period, Account |

### Building PivotTables

1. Load a view into Excel (Data → From ODBC → select view)
2. Insert → PivotTable → From this data
3. Drag fields:
   - **Rows**: Account Name, Cost Center
   - **Columns**: Fiscal Period
   - **Values**: Net Amount (Sum)
   - **Filters**: Legal Entity, Fiscal Year

### Refreshing Data

- Manual: Data → Refresh All
- Automatic: Data → Connections → Properties → Refresh every X minutes

## Budget Input

### Using the Budget Template

1. Open `excel/budget_template.xlsm`
2. Fill in budget lines (entity, period, account, amount)
3. Click "Submit Budget" button (VBA macro sends POST to API)

### Manual API Submission

Use Power Query M formula to POST budget data:
```
= Web.Contents("http://localhost:8080/api/v1/budget", [
    Content = Json.FromValue([lines = budgetTable]),
    Headers = [#"Content-Type" = "application/json"]
])
```

### Budget Validation

After submitting, verify your data:
1. Open Streamlit Admin UI (http://localhost:8501)
2. Go to Scenario Manager → Budget Data Preview
3. Or query directly: `SELECT * FROM v_budget_vs_actual WHERE fiscal_year = 2024`
