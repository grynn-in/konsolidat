# Excel VBA Guide

The Open EPM VBA module turns Excel into a live reporting client. Five worksheet functions query financial data from ClickHouse via the Frappe API. A batch refresh mechanism fetches all values in a single HTTP round-trip.

## Setup

1. Import `excel/OpenEPM.bas` into your workbook (Alt+F11 → File → Import)
2. Add VBA references: `Microsoft Scripting Runtime`, `Microsoft XML, v6.0`
3. Save as `.xlsm`
4. Run `EPM_SetServer` to configure the Frappe URL
5. Run `EPM_Login` to authenticate

See [Setup Guide](../getting-started/setup-guide.md) for full installation steps.

## Formula Functions

All five functions share the same parameter pattern. They differ only in the default `measure` and `scenario`.

### EPM() — General Purpose

```
=EPM(entity, fiscal_year, fiscal_period, account, [measure], [scenario], [cost_center], [department])
```

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `entity` | String | Yes | — | Legal entity code (e.g., `"USMF"`) |
| `fiscal_year` | Number | Yes | — | Fiscal year (e.g., `2024`) |
| `fiscal_period` | String/Number | Yes | — | Period: `1`–`12`, `"Q1"`–`"Q4"`, `"H1"`, `"H2"`, `"FY"` |
| `account` | String | Yes | — | Main account code (e.g., `"401100"`) |
| `measure` | String | No | `"period_net_amount"` | Which value to return (see [Measures](#measures)) |
| `scenario` | String | No | `"actuals"` | Data scenario (see [Scenarios](#scenarios)) |
| `cost_center` | String | No | `""` | Filter by cost center |
| `department` | String | No | `""` | Filter by department |

**Examples:**

```
=EPM("USMF", 2024, 5, "401100")
=EPM("USMF", 2024, "Q1", "401100", "ytd_net_amount")
=EPM("USMF", 2024, "FY", "401100", "period_net_amount", "actuals", "SALES")
```

### EPM_BUDGET() — Budget Values

```
=EPM_BUDGET(entity, fiscal_year, fiscal_period, account, [cost_center], [department])
```

Shorthand for `=EPM(..., "period_amount", "budget", ...)`.

### EPM_VARIANCE() — Actual vs Budget Variance

```
=EPM_VARIANCE(entity, fiscal_year, fiscal_period, account, [cost_center], [department])
```

Shorthand for `=EPM(..., "variance_abs", "variance", ...)`.

### EPM_DEBIT() — Period Debits

```
=EPM_DEBIT(entity, fiscal_year, fiscal_period, account, [cost_center], [department])
```

Shorthand for `=EPM(..., "period_debit", "actuals", ...)`.

### EPM_CREDIT() — Period Credits

```
=EPM_CREDIT(entity, fiscal_year, fiscal_period, account, [cost_center], [department])
```

Shorthand for `=EPM(..., "period_credit", "actuals", ...)`.

## Measures

Each scenario exposes a specific set of measures. Using a measure not allowed for the scenario returns an error.

### Actuals Measures

| Measure | Description |
|---------|-------------|
| `period_debit` | Sum of debit amounts for the period |
| `period_credit` | Sum of credit amounts for the period |
| `period_net_amount` | Sum of accounting currency amount (debit − credit) |
| `transaction_count` | Number of GL entries |
| `ytd_debit` | Year-to-date cumulative debit |
| `ytd_credit` | Year-to-date cumulative credit |
| `ytd_net_amount` | Year-to-date cumulative net amount |

### Budget Measures

| Measure | Description |
|---------|-------------|
| `period_amount` | Budget amount for the specific period (spread from annual) |
| `annual_amount` | Total annual budget amount |

### Variance Measures

| Measure | Description |
|---------|-------------|
| `actual_amount` | Actual amount (from trial balance) |
| `budget_amount` | Budget amount (from spread budget) |
| `variance_abs` | `actual_amount − budget_amount` |
| `variance_pct` | Variance as a percentage of budget |
| `variance_favorable` | `1` if favorable, `0` if unfavorable (revenue: actual > budget; expense: actual < budget) |

## Scenarios

| Scenario | Source Table | Description |
|----------|-------------|-------------|
| `actuals` | `gold_trial_balance` | Posted GL data |
| `budget` | `gold_spread_budget` | Budget amounts spread across periods |
| `variance` | `gold_variance_analysis` | Computed actual-vs-budget comparison |

## Period Ranges

Instead of a single month number, you can pass period range codes. The API sums across the constituent months.

| Code | Months Included |
|------|----------------|
| `1`–`12` | Single month |
| `"Q1"` | Months 1, 2, 3 |
| `"Q2"` | Months 4, 5, 6 |
| `"Q3"` | Months 7, 8, 9 |
| `"Q4"` | Months 10, 11, 12 |
| `"H1"` | Months 1–6 |
| `"H2"` | Months 7–12 |
| `"FY"` | Months 1–12 (full year) |

**Example:** `=EPM("USMF", 2024, "Q1", "401100")` returns the sum of periods 1+2+3.

## Macros

### EPM_Refresh (Ctrl+Shift+R)

Refreshes the **active sheet**:
1. Scans all cells for EPM-family formulas
2. Extracts parameters (resolves cell references like `$B$5`)
3. Sends a single batch POST to `/api/method/konsol.api.epm_batch`
4. Populates the in-memory cache
5. Triggers a single `Calculate` on the EPM range

### EPM_RefreshAll

Refreshes **all sheets** in the workbook. Shows progress on the status bar: `"Open EPM: Sheet 3/12 — Income Statement"`.

### EPM_Login

Prompts for Frappe username and password. Authenticates via `POST /api/method/login` and stores the session cookie for subsequent API calls. Auto-triggered by refresh if not logged in.

### EPM_ClearCache

Clears the in-memory value cache. Use when you want to force a full re-fetch on next refresh.

### EPM_SetServer

Prompts for the Frappe API URL and saves it as a Custom Document Property (`EPM_API_URL`) in the workbook. Persists across sessions.

### EPM_ToggleLog

Enables/disables debug logging to a hidden `_EPM_Log` sheet. Columns: Timestamp, Level, Message.

### EPM_Debug

Runs a diagnostic sequence:
1. Tests cache initialization
2. Tests HTTP connectivity
3. Calls health endpoint (`konsol.api.health`)
4. Scans active sheet for EPM formulas
5. Sends a test batch query (USMF / 2024 / period 5 / account 401100)

## Building a Report

### Basic P&L Report

| | A | B | C | D |
|---|---|---|---|---|
| 1 | **Entity:** | USMF | **Year:** | 2024 |
| 2 | **Account** | **Jan** | **Feb** | **Mar** |
| 3 | Revenue (401100) | `=EPM($B$1,$D$1,1,$A3)` | `=EPM($B$1,$D$1,2,$A3)` | `=EPM($B$1,$D$1,3,$A3)` |
| 4 | COGS (501100) | `=EPM($B$1,$D$1,1,$A4)` | `=EPM($B$1,$D$1,2,$A4)` | `=EPM($B$1,$D$1,3,$A4)` |
| 5 | **Gross Profit** | `=B3+B4` | `=C3+C4` | `=D3+D4` |

Tips:
- Use **absolute references** (`$B$1`) for entity/year cells so formulas copy correctly
- Use **relative row references** for account codes so you can drag formulas down
- Period numbers in the column headers can be cell references too

### Budget vs Actual Report

| | A | B | C | D |
|---|---|---|---|---|
| 1 | **Entity:** | USMF | **Year:** | 2025 |
| 2 | **Account** | **Actual** | **Budget** | **Variance** |
| 3 | Revenue (401100) | `=EPM($B$1,$D$1,"FY",$A3)` | `=EPM_BUDGET($B$1,$D$1,"FY",$A3)` | `=EPM_VARIANCE($B$1,$D$1,"FY",$A3)` |

### Multi-Entity Comparison

Use different entity codes in each column:

```
=EPM("USMF", 2024, "FY", "401100")    ' Column B: US entity
=EPM("DEMF", 2024, "FY", "401100")    ' Column C: Germany entity
=EPM("GBMF", 2024, "FY", "401100")    ' Column D: UK entity
```

## How Refresh Works (Technical)

```mermaid
sequenceDiagram
    participant User
    participant VBA as VBA Module
    participant Cache as Scripting.Dictionary
    participant Frappe as Frappe API
    participant CH as ClickHouse

    User->>VBA: Ctrl+Shift+R
    VBA->>VBA: Scan UsedRange for EPM formulas
    VBA->>VBA: ResolveEpmArgs() — parse & evaluate cell refs
    VBA->>Frappe: POST /api/method/konsol.api.epm_batch<br/>[{entity, year, period, account, ...}, ...]
    Frappe->>Frappe: Validate scenarios & measures
    Frappe->>Frappe: Group by (scenario, measure, periods, dims)
    Frappe->>CH: Parameterized SELECT with SUM + GROUP BY
    CH-->>Frappe: TSV results
    Frappe-->>VBA: {"values": [1234.56, ...]}
    VBA->>Cache: Store key → value
    VBA->>VBA: epmRange.Calculate (single recalc)
    VBA-->>User: Values appear in cells
```

The batch mechanism means 500 EPM cells = 1 HTTP request, not 500.

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| All cells show `0` | Not refreshed | Press Ctrl+Shift+R |
| `#VALUE!` error | Wrong parameter types | Check entity is string, year is number |
| `401` / `403` on refresh | Session expired | Run EPM_Login again |
| Slow refresh | Too many unique queries | Group similar periods; use period ranges (Q1, FY) |
| Values don't update | Stale cache | Run EPM_ClearCache, then Ctrl+Shift+R |
| `ClickHouse connection failed` | ClickHouse is down | Check `docker ps` for healthy container |

## Next Steps

- [Report Catalog](report-catalog.md) — Pre-built report patterns for all 22 gold models
- [Excel Task Pane Guide](excel-taskpane-guide.md) — Pipeline control from Excel
- [API Reference](../api-reference/api-overview.md) — Raw API documentation
- [Troubleshooting](../troubleshooting/troubleshooting.md) — Full diagnostic guide
