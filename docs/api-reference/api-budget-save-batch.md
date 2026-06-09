# POST budget_save_batch

Save multiple budget lines at once. Each item follows the same schema as [budget_save](api-budget-save.md).

## Endpoint

```
POST /api/method/konsol.api.budget_save_batch
```

**Authentication**: Required (Frappe session cookie)

## Request Body

JSON array of budget line objects. Each object has the same fields as `budget_save`.

```json
[
  {
    "scenario_id": "BUDGET_2025",
    "data_area_id": "USMF",
    "fiscal_year": 2025,
    "main_account": "6100",
    "periods": [{"period": 1, "amount": 10000, "layer": "base"}]
  },
  {
    "scenario_id": "BUDGET_2025",
    "data_area_id": "USMF",
    "fiscal_year": 2025,
    "main_account": "6200",
    "periods": [{"period": 1, "amount": 5000, "layer": "base"}]
  }
]
```

## Response

```json
{
  "message": {
    "results": [
      {"name": "BUD-BUDGET_2025-USMF-2025-6100", "index": 0},
      {"name": "BUD-BUDGET_2025-USMF-2025-6200", "index": 1}
    ]
  }
}
```

### With errors (non-blocking)

Invalid items get inline errors; valid items still succeed:

```json
{
  "message": {
    "results": [
      {"name": "BUD-BUDGET_2025-USMF-2025-6100", "index": 0},
      null
    ],
    "errors": [
      null,
      {"index": 1, "error": "Missing required fields: periods"}
    ]
  }
}
```
