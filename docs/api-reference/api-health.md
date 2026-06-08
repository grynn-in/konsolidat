# GET health

A lightweight endpoint for monitoring and connectivity checks. Does **not** require authentication.

## Endpoint

```
GET /api/method/konsol.api.health
```

**Authentication**: None required (`allow_guest=True`)

## Response

```json
{
  "message": {
    "status": "ok",
    "app": "konsol"
  }
}
```

## Example

```bash
curl http://localhost:8069/api/method/konsol.api.health
```

## Usage

### Monitoring / Uptime Checks

Point your monitoring system (UptimeRobot, Pingdom, etc.) at this endpoint. A `200` response with `"status": "ok"` confirms Frappe and the Konsol app are running.

### Docker Health Check

```yaml
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:8069/api/method/konsol.api.health"]
  interval: 30s
  timeout: 5s
  retries: 3
```

### VBA Debug

The `EPM_Debug` macro calls this endpoint as its first connectivity test. If it fails, the Frappe server is unreachable.

## Notes

- This endpoint does **not** verify ClickHouse connectivity. It only confirms the Frappe web server and Konsol app are loaded.
- For a full stack health check (including ClickHouse), see [Monitoring](../admin-guide/monitoring.md).
