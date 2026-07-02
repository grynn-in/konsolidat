# POST budget_cell_save

Save a single budget cell — sets one period on a Budget Sheet's Budget Line. Designed for `EPMSAVE()` immediate writes from Excel.

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

Resolves the **Budget Cycle** for `(scenario_id, fiscal_year)` — auto-created **Open** if absent — then finds or creates the **Budget Sheet** for `(cycle, data_area_id, layer)` and sets the `fiscal_period` cell on the **Budget Line** matching `(main_account, dimensions)`:

- If a matching line exists, that period's amount is updated (other months are preserved).
- If no matching line exists, a new line is appended.
- Once the cycle is **Locked**, the write is refused.

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
    "name": "BSHT-bcyc-budget-2025-2025-usmf-base-1a2b3c4d",
    "value": 15000,
    "modified": "2026-07-02 10:15:00.000000"
  }
}
```

`name` is the Budget Sheet the cell landed in (digest-suffixed: `BSHT-<cycle>-<entity>-<layer>-<sha8>`); `modified` is the new optimistic-locking baseline — pass it back as `base_modified` on the next save of the same sheet to get a `409 conflict` payload instead of a silent overwrite when someone else changed the sheet in between.

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
