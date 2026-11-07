# Excel User Guide

## Connecting Excel to Konsolidat

Excel reads Konsolidat through the `K.` worksheet functions of the Excel
add-in; see the [Excel Formulas guide](user-guide/excel-formulas-guide.md).
The ODBC path through Cube's SQL API and its `v_*` views was removed on
7 Nov 2026 (konsolidat#283). ClickHouse still exposes a PostgreSQL wire port
(15432, loopback by default) for ad-hoc ODBC access on the internal network.

## Budget Entry

### Using the Budget Template

1. Build the template with `=K.EPMSAVE(...)` cells (see the [Excel Formulas Guide](user-guide/excel-formulas-guide.md#write-function))
2. Fill in the amounts
3. Each changed cell is saved to the server when Excel recalculates

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
1. Open Frappe Desk (http://epm.local:8069) and check Budget Sheet records
2. Or query directly: `SELECT * FROM v_budget_vs_actual WHERE fiscal_year = 2024`
