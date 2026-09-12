# POST approve_adjustment

Approve a Consolidation Adjustment that is in "Pending Approval" status. Approval **is** the submit: the adjustment becomes docstatus 1 and reaches the warehouse.

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

1. Applies the workflow action **Approve** (`frappe.model.workflow.apply_workflow`), so the workflow's role and transition checks apply.
2. The adjustment is submitted: `status` becomes "Approved", with `approved_by` (current user) and `approved_at` stamped.
3. After the commit, it syncs to ClickHouse (`epm_staging.consolidation_adjustments`). Only submitted adjustments are synced.
4. The dbt model `gold_consolidation_adjustments` includes it on the next consolidation build.

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

| Cause | Error |
|-------|-------|
| The adjustment isn't in "Pending Approval" | `WorkflowTransitionError`: "Not a valid Workflow Action" |
| Your role may not approve | `WorkflowTransitionError`: "Not a valid Workflow Action" |

Submitting directly (`frappe.client.submit`) or saving `status = "Approved"` on a draft is refused: approval goes through the workflow.

## Workflow Context

```
Draft ──[Send for Approval]──→ Pending Approval ──[Approve = submit]──→ Approved ──[Reverse = cancel]──→ Reversed
                                      │
                                      └──[Reject]──→ Draft
```

Draft and Pending Approval are docstatus 0; Approved is 1; Reversed is 2.

See also: [reverse_adjustment](api-reverse-adjustment.md)
