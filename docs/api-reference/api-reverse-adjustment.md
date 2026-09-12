# POST reverse_adjustment

Reverse an Approved Consolidation Adjustment. Reversal **is** the cancel: the adjustment becomes docstatus 2 and leaves the warehouse. It is allowed only while the adjustment's fiscal period is open.

## Endpoint

```
POST /api/method/konsol.api.reverse_adjustment
```

**Authentication**: Required (Frappe session cookie)

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `name` | string | Yes | Document name of the adjustment to reverse |

## What Happens

1. Applies the workflow action **Reverse** (`frappe.model.workflow.apply_workflow`).
2. Refuses if the adjustment's fiscal period is closed or locked.
3. The adjustment is cancelled: `status` becomes "Reversed".
4. After the commit, ClickHouse is re-synced; the cancelled adjustment is no longer in `epm_staging.consolidation_adjustments`, so the next consolidation build drops it from gold.

No mirror document is created. To correct an adjustment **after its period has closed**, post a new adjustment in an open period. To change an adjustment while its period is open, reverse it and **amend** it: the amendment starts as a fresh Draft and goes through approval again.

## Response

```json
{
  "message": {
    "original": "CADJ-IC001-0001",
    "status": "Reversed"
  }
}
```

## Example

```bash
curl -X POST http://localhost:8069/api/method/konsol.api.reverse_adjustment \
  -H "Content-Type: application/json" \
  -b "cookies.txt" \
  -d '{"name": "CADJ-IC001-0001"}'
```

## Error Responses

| Cause | Error |
|-------|-------|
| The adjustment isn't "Approved" | `WorkflowTransitionError`: "Not a valid Workflow Action" |
| Its fiscal period is closed | `ValidationError`: "Cannot reverse a consolidation adjustment: fiscal period 12 of FY2024 is closed." |

See also: [approve_adjustment](api-approve-adjustment.md)
