# POST reverse_allocation

Reverse an Active Allocation Run (PRD-21). Creates a reversal run and cancels the original.

## Endpoint

```
POST /api/method/konsol.api.reverse_allocation
```

**Authentication**: Required (Frappe session cookie)

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `name` | string | Yes | Document name of the Allocation Run to reverse |

## What Happens

1. Validates the run is in "Active" status
2. Creates a new Allocation Run with `reversal_of` pointing to the original
3. Submits the reversal (becomes Active, synced to ClickHouse)
4. Cancels the original (status set to "Reversed", synced to ClickHouse)

## Response

```json
{
  "message": {
    "original": "ARUN-2025-P6-0001",
    "reversal": "ARUN-2025-P6-0002",
    "status": "Reversed"
  }
}
```

## Example

```bash
curl -X POST http://localhost:8069/api/method/konsol.api.reverse_allocation \
  -H "Content-Type: application/json" \
  -b "cookies.txt" \
  -d '{"name": "ARUN-2025-P6-0001"}'
```

## Error Responses

### Wrong status

```json
{
  "exc_type": "ValidationError",
  "_server_messages": "[\"Cannot reverse: current status is 'Reversed', expected 'Active'\"]"
}
```

## dbt Impact

After reversal:

- Original run: `status = 'Reversed'` — excluded from `gold_allocation_results`
- Reversal run: `status = 'Active'` — included in `gold_allocation_results`
- Both appear in `gold_allocation_audit_trail` for full traceability

See also: [run_allocation](api-run-allocation.md), [allocation_history](api-allocation-history.md)
