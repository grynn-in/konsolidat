# POST epm_batch

Queries multiple financial values in a single request. This is the primary endpoint used by the Excel VBA `EPM_Refresh` macro.

## Endpoint

```
POST /api/method/konsol.api.epm_batch
```

**Authentication**: Required (Frappe session cookie)

## Request

Send a JSON array as the raw POST body. Each element is a request object.

### Request Object

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `entity` | string | Yes | — | Legal entity code |
| `year` | integer | Yes | — | Fiscal year |
| `period` | string/int | Yes | — | Period: `1`–`12`, `Q1`–`Q4`, `H1`, `H2`, `FY` |
| `account` | string | Yes | — | Main account code |
| `measure` | string | No | `period_net_amount` | Measure name |
| `scenario` | string | No | `actuals` | Scenario: `actuals`, `budget`, `variance` |
| `cost_center` | string | No | `""` | Cost center filter |
| `department` | string | No | `""` | Department filter |

### Size Limit

Maximum **2000** items per request (`MAX_BATCH_SIZE`). Requests exceeding this limit are rejected.

## Response

```json
{
  "message": {
    "values": [125430.50, 0.0, 89200.00, null],
    "errors": [
      {"index": 3, "error": "Measure foo not allowed for scenario actuals. Allowed: period_debit, period_credit, period_net_amount, transaction_count, ytd_debit, ytd_credit, ytd_net_amount"}
    ]
  }
}
```

### Response Fields

| Field | Type | Description |
|-------|------|-------------|
| `values` | array | One value per request item, positionally matched. `null` for items with errors. |
| `errors` | array | Only present when at least one item fails validation. Each error has `index` (0-based) and `error` message. |

### Value Handling

- Successful queries return `float` values
- No matching data returns `0.0`
- `null` in the values array indicates an error for that item (check `errors`)
- The VBA module treats `null` as `0`

## Example

### curl

```bash
curl -X POST "http://localhost:8069/api/method/konsol.api.epm_batch" \
  -H "Content-Type: application/json" \
  -b "cookies.txt" \
  -d '[
    {"entity": "USMF", "year": 2024, "period": 5, "account": "401100"},
    {"entity": "USMF", "year": 2024, "period": 5, "account": "501100"},
    {"entity": "DEMF", "year": 2024, "period": "Q1", "account": "401100", "measure": "period_net_amount"},
    {"entity": "USMF", "year": 2025, "period": "FY", "account": "6100", "measure": "period_amount", "scenario": "budget"},
    {"entity": "USMF", "year": 2024, "period": 5, "account": "401100", "measure": "variance_abs", "scenario": "variance", "cost_center": "SALES"}
  ]'
```

### Python

```python
import requests

session = requests.Session()
session.post("http://localhost:8069/api/method/login",
             json={"usr": "admin", "pwd": "password"})

response = session.post(
    "http://localhost:8069/api/method/konsol.api.epm_batch",
    json=[
        {"entity": "USMF", "year": 2024, "period": 5, "account": "401100"},
        {"entity": "USMF", "year": 2024, "period": 5, "account": "501100"},
    ]
)

data = response.json()["message"]
print(data["values"])  # [125430.50, 89200.00]
```

## Query Grouping Optimization

The batch endpoint doesn't issue one SQL query per item. Instead, it groups items by:

```
(scenario, measure, period_tuple, has_cost_center, has_department)
```

All items in a group are fetched with a single ClickHouse `SELECT` using parameterized `IN` clauses:

```sql
SELECT data_area_id, fiscal_year, main_account,
       coalesce(sum(period_net_amount), 0) as val
FROM epm_gold.gold_trial_balance
WHERE data_area_id IN ({e0:String}, {e1:String})
  AND fiscal_year IN ({y0:Int32}, {y1:Int32})
  AND main_account IN ({a0:String}, {a1:String})
  AND fiscal_period IN ({fp0:Int32}, {fp1:Int32}, {fp2:Int32})
GROUP BY data_area_id, fiscal_year, main_account
```

This means:
- 200 actuals/period_net_amount cells for months 1–3 → 1 SQL query
- 100 budget cells + 50 variance cells → 2 SQL queries
- Net result: a 350-cell refresh produces ~2–3 queries instead of 350

## Error Handling

Per-item validation runs before query grouping. Invalid items get inline errors while valid items proceed normally.

| Error | Trigger |
|-------|---------|
| `Invalid scenario: {x}` | Scenario not in `actuals`, `budget`, `variance` |
| `Measure {x} not allowed for scenario {y}` | Measure/scenario mismatch |
| `Batch size {n} exceeds maximum of 2000` | Array too large (rejects entire request) |
| `ClickHouse query timeout` | ClickHouse query exceeded 30s |
| `ClickHouse connection failed` | ClickHouse unreachable |

ClickHouse errors apply to all items in the affected query group.

## HTTP Timeouts

The VBA module sets these timeouts when calling the batch endpoint:

| Phase | Timeout |
|-------|---------|
| Resolve | 5,000 ms |
| Connect | 10,000 ms |
| Send | 30,000 ms |
| Receive | 60,000 ms |

The Frappe-to-ClickHouse query uses a 30-second `requests` timeout.
