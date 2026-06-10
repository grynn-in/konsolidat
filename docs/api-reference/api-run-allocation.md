# POST run_allocation

Create and execute an Allocation Run for a given fiscal period.

## Endpoint

```
POST /api/method/konsol.api.run_allocation
```

**Authentication**: Required (Frappe session cookie)

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `fiscal_year` | integer | Yes | Fiscal year (e.g., `2025`) |
| `fiscal_period` | integer | Yes | Fiscal period (`1`–`12`) |

## What Happens

1. Creates a new Allocation Run document
2. Submits it (triggers `before_submit`):
    - `allocation_run_id` set to the document name
    - `run_by` set to the current user
    - `run_at` set to the current timestamp
    - `status` set to "Active"
3. Syncs to ClickHouse (`epm_staging.allocation_runs`)
4. dbt model `gold_allocation_results` includes this run (filters `status = 'Active'`)

## Response

```json
{
  "message": {
    "name": "ARUN-2025-P6-0001",
    "allocation_run_id": "ARUN-2025-P6-0001",
    "status": "Active",
    "run_by": "admin@example.com",
    "run_at": "2025-06-09 14:30:00"
  }
}
```

## Example

```bash
curl -X POST http://localhost:8069/api/method/konsol.api.run_allocation \
  -H "Content-Type: application/json" \
  -b "cookies.txt" \
  -d '{"fiscal_year": 2025, "fiscal_period": 6}'
```

## Workflow Context

```
Draft ──[Run Allocation]──→ Running ──[Complete]──→ Active ──[Reverse]──→ Reversed
```

See also: [reverse_allocation](api-reverse-allocation.md), [allocation_history](api-allocation-history.md)
