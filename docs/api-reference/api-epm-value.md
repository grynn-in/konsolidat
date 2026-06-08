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
| `measure` | string | No | `period_net_amount` | Measure name ([see allowed measures](api-overview.md#scenario--table-mapping)) |
| `scenario` | string | No | `actuals` | Scenario: `actuals`, `budget`, `variance` |
| `cost_center` | string | No | `""` | Cost center filter |
| `department` | string | No | `""` | Department filter |

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

### With dimension filters

```bash
curl "http://localhost:8069/api/method/konsol.api.epm_value?\
entity=USMF&year=2024&period=FY&account=401100&\
cost_center=SALES&department=SALES" \
  -b "cookies.txt"
```

## Error Responses

### Invalid scenario

```json
{
  "exc_type": "ValidationError",
  "_server_messages": "[\"Invalid scenario: forecast. Allowed: actuals, budget, variance\"]"
}
```

### Invalid measure for scenario

```json
{
  "exc_type": "ValidationError",
  "_server_messages": "[\"Measure ytd_net_amount not allowed for scenario budget. Allowed: period_amount, annual_amount\"]"
}
```

## Notes

- For bulk queries (e.g., refreshing an Excel sheet), use [epm_batch](api-epm-batch.md) instead — it's significantly more efficient.
- Internally, `epm_value` delegates to the same `_batch_query_clickhouse()` function used by the batch endpoint.
- The `period` parameter accepts both integers and strings. The API normalizes `"5"` to `(5,)` and `"Q1"` to `(1, 2, 3)`.
