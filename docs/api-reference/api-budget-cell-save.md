# POST budget_cell_save

Save a single budget cell — upserts one period+layer row in a Budget Input document. Designed for `EPMSAVE()` immediate writes from Excel.

## Endpoint

```
POST /api/method/konsol.api.budget_cell_save
```

**Authentication**: Required (Frappe session cookie)

## Request Body

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `scenario_id` | string | Yes | Scenario identifier (e.g., `BUDGET_2025`) |
| `data_area_id` | string | Yes | Entity code (e.g., `USMF`) |
| `fiscal_year` | integer | Yes | Fiscal year |
| `main_account` | string | Yes | Account code |
| `fiscal_period` | integer | Yes | Period number (`1`–`12`) |
| `amount` | number | Yes | Budget amount |
| `layer` | string | Yes | Budget layer: `base`, `challenge`, `management`, `board` |
| `dim_cost_center` | string | No | Cost center dimension |
| `dim_department` | string | No | Department dimension |

## Upsert Behavior

Finds or creates the Budget Input document by `(scenario_id, data_area_id, fiscal_year, main_account)`, then upserts the specific period+layer row within it:

- If a row with the same `fiscal_period` + `layer` exists, its amount is updated.
- If no matching row exists, a new period row is appended.

## Example

```bash
curl -X POST http://localhost:8069/api/method/konsol.api.budget_cell_save \
  -H "Content-Type: application/json" \
  -b "cookies.txt" \
  -d '{
    "scenario_id": "BUDGET_2025",
    "data_area_id": "USMF",
    "fiscal_year": 2025,
    "main_account": "6100",
    "fiscal_period": 3,
    "amount": 15000,
    "layer": "base"
  }'
```

## Response

```json
{
  "message": {
    "status": "ok",
    "name": "BUD-BUDGET_2025-USMF-2025-6100",
    "value": 15000
  }
}
```

## Error Responses

### Invalid layer

```json
{
  "exc_type": "ValidationError",
  "_server_messages": "[\"Invalid layer 'forecast'. Allowed: base, board, challenge, management\"]"
}
```

### Invalid fiscal period

```json
{
  "exc_type": "ValidationError",
  "_server_messages": "[\"fiscal_period must be 1-12\"]"
}
```
