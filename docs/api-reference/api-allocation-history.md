# GET allocation_history

List allocation run history with optional filters. Returns all runs (Active + Reversed) for audit trail purposes.

## Endpoint

```
GET /api/method/konsol.api.allocation_history
```

**Authentication**: Required (Frappe session cookie)

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `fiscal_year` | integer | No | Filter by fiscal year |
| `fiscal_period` | integer | No | Filter by fiscal period |

## Response

```json
{
  "message": {
    "runs": [
      {
        "name": "ARUN-2025-P6-0002",
        "allocation_run_id": "ARUN-2025-P6-0002",
        "fiscal_year": 2025,
        "fiscal_period": 6,
        "status": "Active",
        "run_by": "admin@example.com",
        "run_at": "2025-06-09 15:00:00",
        "reversal_of": "ARUN-2025-P6-0001"
      },
      {
        "name": "ARUN-2025-P6-0001",
        "allocation_run_id": "ARUN-2025-P6-0001",
        "fiscal_year": 2025,
        "fiscal_period": 6,
        "status": "Reversed",
        "run_by": "admin@example.com",
        "run_at": "2025-06-09 14:30:00",
        "reversal_of": null
      }
    ]
  }
}
```

## Run Object

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Frappe document name |
| `allocation_run_id` | string | Run identifier (set on submit) |
| `fiscal_year` | integer | Fiscal year |
| `fiscal_period` | integer | Fiscal period |
| `status` | string | `Draft`, `Running`, `Active`, or `Reversed` |
| `run_by` | string | User who executed the run |
| `run_at` | string | Execution timestamp |
| `reversal_of` | string/null | Original run name (if this is a reversal) |

## Examples

### All runs

```bash
curl "http://localhost:8069/api/method/konsol.api.allocation_history" \
  -b "cookies.txt"
```

### Filtered by period

```bash
curl "http://localhost:8069/api/method/konsol.api.allocation_history?\
fiscal_year=2025&fiscal_period=6" \
  -b "cookies.txt"
```

Runs are ordered by `run_at` descending (most recent first).

See also: [run_allocation](api-run-allocation.md), [reverse_allocation](api-reverse-allocation.md)
