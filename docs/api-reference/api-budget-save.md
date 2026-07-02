# POST budget_save

Save a single budget line — creates or updates Budget Line rows in the matching (cycle × entity × layer) Budget Sheet(s).

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

The endpoint resolves the **Budget Cycle** for `(scenario_id, fiscal_year)` — auto-created **Open** if absent — then writes each period into the **Budget Sheet** for `(cycle, data_area_id, layer)`, creating the sheet if new. A payload mixing layers fans out across sheets. Within a sheet, the **Budget Line** is matched by `(main_account, dimensions)`; only the supplied periods are touched — unspecified months on an existing line are preserved. Writes are refused once the cycle is **Locked**.

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
    "sheets": ["BSHT-bcyc-budget-2025-2025-usmf-base-1a2b3c4d"],
    "name": "BSHT-bcyc-budget-2025-2025-usmf-base-1a2b3c4d"
  }
}
```

`sheets` lists every Budget Sheet the payload touched (one per layer); `name` is the first for backward compatibility. Sheet names are digest-suffixed (`BSHT-<cycle>-<entity>-<layer>-<sha8>`).

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
