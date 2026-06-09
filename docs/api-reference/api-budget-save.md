# POST budget_save

Save a single budget line — creates or updates a Budget Input document in Draft status.

## Endpoint

```
POST /api/method/konsol.api.budget_save
```

**Authentication**: Required (Frappe session cookie)

## Request Body

JSON object with the following fields:

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `scenario_id` | string | Yes | Scenario identifier (e.g., `BUDGET_2025`) |
| `data_area_id` | string | Yes | Entity code (e.g., `USMF`) |
| `fiscal_year` | integer | Yes | Fiscal year (e.g., `2025`) |
| `main_account` | string | Yes | Account code (e.g., `6100`) |
| `dim_cost_center` | string | No | Cost center dimension |
| `dim_department` | string | No | Department dimension |
| `periods` | array | Yes | Period amounts (see below) |

### Period Object

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `period` | integer | Yes | Fiscal period (`1`–`12`) |
| `amount` | number | Yes | Budget amount |
| `layer` | string | No | Budget layer: `base` (default), `challenge`, `management`, `board` |

## Upsert Behavior

The endpoint upserts by the unique key `(scenario_id, data_area_id, fiscal_year, main_account)`. If a matching Budget Input document exists, its period rows are replaced. Otherwise, a new document is created.

## Example

```bash
curl -X POST http://localhost:8069/api/method/konsol.api.budget_save \
  -H "Content-Type: application/json" \
  -b "cookies.txt" \
  -d '{
    "scenario_id": "BUDGET_2025",
    "data_area_id": "USMF",
    "fiscal_year": 2025,
    "main_account": "6100",
    "dim_cost_center": "CC001",
    "periods": [
      {"period": 1, "amount": 10000, "layer": "base"},
      {"period": 2, "amount": 12000, "layer": "base"},
      {"period": 3, "amount": 11000, "layer": "base"}
    ]
  }'
```

## Response

```json
{
  "message": {
    "name": "BUD-BUDGET_2025-USMF-2025-6100"
  }
}
```

## Error Responses

### Missing required fields

```json
{
  "exc_type": "ValidationError",
  "_server_messages": "[\"Missing required fields: main_account, periods\"]"
}
```

### Invalid periods format

```json
{
  "exc_type": "ValidationError",
  "_server_messages": "[\"periods must be a non-empty array\"]"
}
```
