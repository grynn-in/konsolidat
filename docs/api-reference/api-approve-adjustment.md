# POST approve_adjustment

Approve a Consolidation Adjustment that is in "Pending Approval" status (PRD-16).

## Endpoint

```
POST /api/method/konsol.api.approve_adjustment
```

**Authentication**: Required (Frappe session cookie)

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `name` | string | Yes | Document name (e.g., `CADJ-IC001-0001`) |

## What Happens

1. Validates the adjustment is in "Pending Approval" status
2. Sets `status` to "Approved"
3. Records `approved_by` (current user) and `approved_at` (timestamp)
4. Saves and syncs to ClickHouse (`epm_staging.consolidation_adjustments`)
5. dbt model `gold_consolidation_adjustments` will include this entry (filters `status IN ('Approved', 'Reversed')`)

## Response

```json
{
  "message": {
    "status": "Approved",
    "approved_by": "admin@example.com",
    "approved_at": "2025-06-09 14:30:00"
  }
}
```

## Error Responses

### Wrong status

```json
{
  "exc_type": "ValidationError",
  "_server_messages": "[\"Cannot approve: current status is 'Draft', expected 'Pending Approval'\"]"
}
```

## Workflow Context

```
Draft ──[Submit for Approval]──→ Pending Approval ──[Approve]──→ Approved ──[Reverse]──→ Reversed
                                        │
                                        └──[Reject]──→ Draft
```

See also: [reverse_adjustment](api-reverse-adjustment.md)
