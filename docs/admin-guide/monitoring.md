# Monitoring

Health checks, log monitoring, and alerting for Open EPM.

## Health Endpoints

### Frappe / Konsol API

```bash
curl http://localhost:8069/api/method/konsol.api.health
# {"message": {"status": "ok", "app": "konsol"}}
```

- **Guest-accessible** — no auth needed
- Confirms Frappe web server and Konsol app are running
- Does **not** test ClickHouse connectivity

### ClickHouse

```bash
curl "http://localhost:8123/?query=SELECT+1"
# 1

# Or via Docker health check:
docker inspect --format='{{.State.Health.Status}}' open_epm_clickhouse
# healthy
```

### Full Stack Check

Test the complete path (Frappe → ClickHouse):

```bash
# Login first
curl -c cookies.txt -X POST http://localhost:8069/api/method/login \
  -H "Content-Type: application/json" \
  -d '{"usr": "admin", "pwd": "password"}'

# Query via API
curl -b cookies.txt "http://localhost:8069/api/method/konsol.api.epm_value?\
entity=USMF&year=2024&period=1&account=401100"
```

A successful response with a numeric value confirms the entire pipeline is working.

## ClickHouse System Tables

### Query Performance

```sql
-- Slowest queries in the last hour
SELECT
    query_start_time,
    query_duration_ms,
    read_rows,
    formatReadableSize(read_bytes) as data_read,
    query
FROM system.query_log
WHERE type = 'QueryFinish'
  AND query_start_time > now() - INTERVAL 1 HOUR
ORDER BY query_duration_ms DESC
LIMIT 10
```

### Database Sizes

```sql
SELECT
    database,
    formatReadableSize(sum(bytes_on_disk)) as disk_size,
    formatReadableQuantity(sum(rows)) as total_rows,
    count() as parts
FROM system.parts
WHERE active AND database LIKE 'epm_%'
GROUP BY database
ORDER BY sum(bytes_on_disk) DESC
```

### Table-Level Detail

```sql
SELECT
    database,
    table,
    formatReadableSize(sum(bytes_on_disk)) as size,
    formatReadableQuantity(sum(rows)) as rows
FROM system.parts
WHERE active AND database = 'epm_gold'
GROUP BY database, table
ORDER BY sum(bytes_on_disk) DESC
```

### Active Connections

```sql
SELECT * FROM system.processes
```

### Error Log

```sql
SELECT
    event_time,
    message
FROM system.text_log
WHERE level = 'Error'
  AND event_time > now() - INTERVAL 1 DAY
ORDER BY event_time DESC
LIMIT 20
```

## Frappe Logs

### Log Files

| Log | Path | Content |
|-----|------|---------|
| Web | `~/frappe-bench/logs/web.log` | HTTP requests to Frappe |
| Worker | `~/frappe-bench/logs/worker.log` | Background job execution |
| Frappe | `~/frappe-bench/logs/frappe.log` | Application errors |
| Scheduler | `~/frappe-bench/logs/scheduler.log` | Scheduled tasks |

### Tail API Errors

```bash
grep "konsol.api" ~/frappe-bench/logs/frappe.log | tail -20
```

### Common Error Patterns

| Log Pattern | Meaning |
|------------|---------|
| `ClickHouse connection failed` | ClickHouse unreachable from Frappe |
| `ClickHouse query timeout` | Query exceeded 30s |
| `ValidationError: Invalid scenario` | Client sent bad scenario value |
| `403 Forbidden` | User not logged in or lacks permission |

## Monitoring Setup

### UptimeRobot / Pingdom

Point at: `https://epm.yourcompany.com/api/method/konsol.api.health`
- Expected: HTTP 200 with `"status": "ok"`
- Alert on: Non-200 or timeout

### Docker Health Checks

Already configured in `docker-compose.yml`:

```yaml
healthcheck:
  test: ["CMD", "clickhouse-client", "--query", "SELECT 1"]
  interval: 10s
  timeout: 5s
  retries: 5
```

### dbt Test Monitoring

After each `dbt build`, check exit code:

```bash
dbt build && echo "SUCCESS" || echo "FAILED — check test output"
```

For scheduled runs, pipe test results to a log or alert system:

```bash
dbt test --output json > /var/log/dbt-test-results.json 2>&1
```

### Alert Thresholds

| Metric | Warning | Critical |
|--------|---------|----------|
| API response time | > 2s | > 10s |
| ClickHouse query time | > 5s | > 30s (timeout) |
| ClickHouse disk usage | > 70% | > 90% |
| dbt test failures | Any `warn` severity | Any `error` severity |
| Airbyte sync failure | — | Any failure |

## VBA Debug Logging

The Excel VBA module includes a built-in logging system:

1. Run `EPM_ToggleLog` to enable logging
2. A hidden `_EPM_Log` sheet captures:
   - Timestamp
   - Level (INFO, ERROR, DEBUG)
   - Message (HTTP requests, responses, parse results)
3. Run `EPM_Debug` for a full diagnostic test

## Next Steps

- [Operations Runbook](operations-runbook.md) — Maintenance procedures
- [Deployment Guide](deployment-guide.md) — Infrastructure setup
- [Troubleshooting](../troubleshooting/troubleshooting.md) — Problem resolution
