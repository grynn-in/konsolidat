# POST reverse_adjustment

Reverse an Approved Consolidation Adjustment. Creates a reversal document with negated amounts and links both via `reversal_journal_id`.

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

1. Validates the adjustment is in "Approved" status
2. Creates a new Consolidation Adjustment with:
    - Debit/credit amounts swapped (reversal)
    - `journal_id` prefixed with `REV-`
    - `status` set to "Approved"
    - `reversal_journal_id` pointing to the original
3. Submits the reversal document
4. Marks the original as "Reversed" with `reversal_journal_id` pointing to the reversal
5. Both synced to ClickHouse

## Response

```json
{
  "message": {
    "original": "CADJ-IC001-0001",
    "reversal": "CADJ-REV-IC001-0002",
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

### Wrong status

```json
{
  "exc_type": "ValidationError",
  "_server_messages": "[\"Cannot reverse: current status is 'Pending Approval', expected 'Approved'\"]"
}
```

## dbt Impact

The `gold_consolidation_adjustments` model includes both the original (now "Reversed") and the reversal (status "Approved") entries. The reversal's negated amounts cancel out the original, producing a net-zero effect on consolidated results.

See also: [approve_adjustment](api-approve-adjustment.md)
