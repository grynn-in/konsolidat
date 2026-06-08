# Operations Runbook

Day-to-day and monthly procedures for maintaining Konsolidat.

## Monthly Close Procedure

### 1. Sync D365 Data

Trigger an Airbyte sync to pull the latest GL entries and reference data.

**From Excel Task Pane**: Click "Trigger Pipeline" button.

**From CLI**:
```bash
# Via Airbyte API
curl -X POST http://localhost:8000/api/v1/connections/sync \
  -H "Content-Type: application/json" \
  -d '{"connectionId": "YOUR_CONNECTION_ID"}'
```

### 2. Run dbt Build

After Airbyte sync completes:

```bash
cd /path/to/konsolidat/dbt_project
dbt build
```

This will:
1. Build all 44 models (bronze → silver → gold)
2. Run all 26 tests
3. Report any failures

### 3. Verify Test Results

Check for test failures:

```bash
dbt test
```

Critical tests for month-end:
- `assert_trial_balance_balances` — debits = credits per entity/period
- `assert_silver_gl_debit_credit_balance` — GL-level balance check
- `assert_spread_sums_to_annual` — budget integrity
- `assert_ic_elimination_nets_zero` — IC elimination check
- `assert_fctb_entity_layer_ties` — consolidation integrity

### 4. Refresh Excel Reports

In Excel: run **EPM_ClearCache** then **EPM_RefreshAll** (or Ctrl+Shift+R per sheet).

### 5. Review Consolidation

Check consolidated trial balance for:
- CTA amounts (non-zero when FX rates differ)
- IC eliminations (should net to zero)
- Top-side journals (balanced)
- NCI split (correct ownership percentages)

## Common dbt Commands

| Command | Description |
|---------|-------------|
| `dbt build` | Full build: run models + tests |
| `dbt run` | Run models only (no tests) |
| `dbt test` | Run tests only |
| `dbt seed` | Load/reload seed CSVs |
| `dbt run --select gold_trial_balance+` | Run one model and downstream |
| `dbt run --select tag:gold` | Run all gold models |
| `dbt test --select gold_trial_balance` | Test one model |
| `dbt build --full-refresh` | Drop and rebuild all tables |
| `dbt debug` | Verify dbt configuration and connectivity |

## Seed Management

### Updating Reference Data

1. Edit the CSV file in `dbt_project/seeds/`
2. Run `dbt seed` to reload
3. Run `dbt build` to rebuild dependent models

### Key Seeds

| Seed | When to Update |
|------|---------------|
| `consolidation_groups.csv` | New entity, ownership change |
| `allocation_rules.csv` | New allocation rule |
| `allocation_drivers_*.csv` | Monthly driver values |
| `budget_annual_input.csv` | Annual budget cycle |
| `spread_profiles.csv` | New spread pattern |
| `consolidation_adjustments.csv` | Top-side journals |
| `ic_elimination_rules.csv` | New IC patterns |
| `entity_fiscal_calendars.csv` | New entity or calendar change |

## ClickHouse Maintenance

### Check Database Sizes

```sql
SELECT database, formatReadableSize(sum(bytes_on_disk)) as size
FROM system.parts
WHERE active
GROUP BY database
ORDER BY sum(bytes_on_disk) DESC
```

### Check Table Row Counts

```sql
SELECT database, table, formatReadableQuantity(sum(rows)) as rows
FROM system.parts
WHERE active AND database LIKE 'epm_%'
GROUP BY database, table
ORDER BY database, table
```

### Optimize Tables (After Large Loads)

```sql
OPTIMIZE TABLE epm_gold.gold_trial_balance FINAL
```

### Check Running Queries

```sql
SELECT query_id, elapsed, query
FROM system.processes
ORDER BY elapsed DESC
```

## Frappe Maintenance

### Backup

```bash
cd ~/frappe-bench
bench --site konsolidat.local backup
```

Backups are saved to `~/frappe-bench/sites/konsolidat.local/private/backups/`.

### Clear Cache

```bash
bench --site konsolidat.local clear-cache
```

### Restart Workers

```bash
bench restart
```

### Check Logs

```bash
# Frappe web log
tail -f ~/frappe-bench/logs/web.log

# Worker log
tail -f ~/frappe-bench/logs/worker.log

# Frappe error log
tail -f ~/frappe-bench/logs/frappe.log
```

## Troubleshooting Quick Checks

| Issue | Check |
|-------|-------|
| API returning errors | `tail ~/frappe-bench/logs/frappe.log` |
| ClickHouse down | `docker ps` — check health status |
| dbt test failure | `dbt test --select test_name` — read assertion |
| Stale data | Check Airbyte sync status, re-trigger if needed |
| Slow queries | `SELECT * FROM system.query_log ORDER BY query_duration_ms DESC LIMIT 10` |

## Scheduled Tasks

| Task | Frequency | Method |
|------|-----------|--------|
| Airbyte D365 sync | Daily / on-demand | Airbyte scheduler or API |
| dbt build | After sync completes | Cron or Pipeline Run |
| Frappe backup | Daily | `bench backup` via cron |
| ClickHouse backup | Weekly | `clickhouse-backup` or volume snapshot |
| Log rotation | Weekly | OS logrotate |

## Next Steps

- [Monitoring](monitoring.md) — Automated health checks
- [Deployment Guide](deployment-guide.md) — Infrastructure setup
- [Troubleshooting](../troubleshooting/troubleshooting.md) — Detailed problem resolution
