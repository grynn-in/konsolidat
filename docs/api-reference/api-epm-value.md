# GET epm_value

Returns a single financial value for the given dimension combination.

## Endpoint

```
GET /api/method/konsol.api.epm_value
```

**Authentication**: Required (Frappe session cookie)

## Parameters

All parameters are passed as query string arguments.

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `entity` | string | Yes | — | Legal entity code (e.g., `USMF`) |
| `year` | integer | Yes | — | Fiscal year (e.g., `2024`) |
| `period` | string/int | Yes | — | Fiscal period: `1`–`12`, `Q1`–`Q4`, `H1`, `H2`, `FY` |
| `account` | string | Yes | — | Main account code (e.g., `401100`) |
| `measure` | string | No | `period_net_amount` | Measure name. Validated against the active **Measure** registry intersected with the fact's allowed measures. |
| `fact` | string | No | — | Fact registry name (e.g. `gl_journal_entries`, `budget_input`, `headcount`) selecting the source table. Case-insensitive. **Wins over `scenario`** when both are given. |
| `dimensions` | string (JSON) | No | `{}` | Dimension filters as a JSON object, e.g. `{"dim_cost_center":"CC001","dim_project":"P01"}`. Keys are canonical dimension names; validated against the fact's allowed dimensions. This is the only way to filter by dimension. |
| `scenario` | string | No | `actuals` | Resolves the fact via its `scenario_key` when `fact` is not supplied. |
| `scenario_id` | string | No | `""` | Filter to a specific scenario (e.g., `BUDGET_2025`). Only applies to facts whose `has_scenario_id` flag is set (e.g. `budget_input`). When empty, returns the sum across all scenario IDs. |

> **Dynamic schema (Phase 2.4):** dimensions, measures, and facts are registry-driven (Frappe `Dimension`, `Measure`, `Fact Table` doctypes). Adding a dimension/measure/fact is a registry operation — the API requires no code change. There is no fixed scenario→table map; `fact` (or legacy `scenario`) resolves to a `Fact Table.clickhouse_table`.

## Period Resolution

| Input | Resolved Periods |
|-------|-----------------|
| `1`–`12` | Single month `(N,)` |
| `Q1` | `(1, 2, 3)` |
| `Q2` | `(4, 5, 6)` |
| `Q3` | `(7, 8, 9)` |
| `Q4` | `(10, 11, 12)` |
| `H1` | `(1, 2, 3, 4, 5, 6)` |
| `H2` | `(7, 8, 9, 10, 11, 12)` |
| `FY` | `(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12)` |

When a period range resolves to multiple months, the API returns the **sum** across those months.

## Response

```json
{
  "message": {
    "value": 125430.50
  }
}
```

## Examples

### Basic: Net amount for a single period

```bash
curl "http://localhost:8069/api/method/konsol.api.epm_value?\
entity=USMF&year=2024&period=5&account=401100" \
  -b "cookies.txt"
```

### With measure and scenario

```bash
curl "http://localhost:8069/api/method/konsol.api.epm_value?\
entity=USMF&year=2025&period=Q1&account=6100&\
measure=period_amount&scenario=budget" \
  -b "cookies.txt"
```

### With generic dimension filters (Phase 2.4)

```bash
# dimensions is a URL-encoded JSON object: {"dim_cost_center":"SALES","dim_project":"P01"}
curl "http://localhost:8069/api/method/konsol.api.epm_value?\
entity=USMF&year=2024&period=FY&account=401100&\
dimensions=%7B%22dim_cost_center%22%3A%22SALES%22%2C%22dim_project%22%3A%22P01%22%7D" \
  -b "cookies.txt"
```

### Selecting a fact by name (Phase 2.4)

```bash
curl "http://localhost:8069/api/method/konsol.api.epm_value?\
entity=USMF&year=2024&period=FY&account=401100&\
fact=headcount&measure=driver_value" \
  -b "cookies.txt"
```

### With scenario_id filter

```bash
curl "http://localhost:8069/api/method/konsol.api.epm_value?\
entity=USMF&year=2025&period=Q1&account=6100&\
measure=period_amount&scenario=budget&scenario_id=BUDGET_2025" \
  -b "cookies.txt"
```

## Error Responses

### Invalid fact

```json
{
  "exc_type": "ValidationError",
  "_server_messages": "[\"Invalid fact 'forecast'. Allowed: budget_input, gl_journal_entries, headcount, ...\"]"
}
```

### Invalid measure for fact

```json
{
  "exc_type": "ValidationError",
  "_server_messages": "[\"Invalid measure 'ytd_net_amount' for fact 'budget_input'. Allowed: annual_amount, period_amount\"]"
}
```

### Invalid dimension for fact

```json
{
  "exc_type": "ValidationError",
  "_server_messages": "[\"Invalid dimension 'dim_project' for fact 'gl_journal_entries'. Allowed: dim_business_unit, dim_cost_center, dim_department\"]"
}
```

## Notes

- For bulk queries (e.g., refreshing an Excel sheet), use [epm_batch](api-epm-batch.md) instead — it's significantly more efficient.
- Internally, `epm_value` delegates to the same `_batch_query_clickhouse()` function used by the batch endpoint.
- The `period` parameter accepts both integers and strings. The API normalizes `"5"` to `(5,)` and `"Q1"` to `(1, 2, 3)`.
