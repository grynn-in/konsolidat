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

Before building, check that the period's **Group Exchange Rates** are approved in konsol (the month's "Ownership & rates" stage shows any that are missing). A translated currency without an approved Closing and Average rate stops the consolidation build; see [Exchange-rate problems](#exchange-rate-problems).

After Airbyte sync completes:

```bash
cd /path/to/konsolidat/dbt_project
dbt build
```

This will:
1. Build all 103 models (staging → bronze → silver → allocated → gold)
2. Run the 110 singular tests in `dbt_project/tests/` plus the generic tests declared in the model YAML
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

In Excel: recalculate all formulas (**Ctrl+Alt+F9**).

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
| `dbt run --select gold_trial_balance+` | Run one model and downstream |
| `dbt run --select tag:gold` | Run all gold models |
| `dbt test --select gold_trial_balance` | Test one model |
| `dbt build --full-refresh` | Drop and rebuild all tables |
| `dbt debug` | Verify dbt configuration and connectivity |

## Reference Data

There are no dbt seeds: `dbt_project/seeds/` was deleted (konsolidat #144, #145, #147). Reference and configuration data lives in konsol doctypes. Saving a record (or approving it, for documents that need approval) writes it through to the ClickHouse table dbt reads, and the next `dbt build` picks it up. Do not edit those tables by hand: konsol overwrites them on the next write-through.

### Key Doctypes

| Doctype (konsol) | When to Update |
|------|---------------|
| **Consolidation Group** | New entity, new sub-group, reporting currency |
| **Ownership Period** | Ownership or consolidation method change |
| **Group Exchange Rate** | Every period: approved Closing and Average rates (see the [Exchange Rates Guide](../user-guide/exchange-rates-guide.md)) |
| **Intercompany Account** | New intercompany account pair (see the [Intercompany Guide](../user-guide/intercompany-guide.md)) |
| **Consolidation Adjustment** | Top-side journals (EPM Analyst drafts, EPM Admin approves) |
| **Allocation Rule**, **Allocation Driver** | New allocation rule; monthly driver values |
| **Budget Annual Input**, **Spread Profile** | Annual budget cycle; new spread pattern |
| **Entity Fiscal Calendar** | New entity or calendar change |

The [Configuration Data](../data-dictionary/seeds-reference.md) page maps every former seed to its doctype and warehouse table.

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
| Build refused: "translated key(s) without a usable governed rate" | [Exchange-rate problems](#exchange-rate-problems) |
| `bench migrate` stops: "no magnitude reference (ISO Currency usd_log10)" | [Exchange-rate problems](#exchange-rate-problems) |

## Exchange-rate problems

What `deploy.sh` does around exchange rates is described once, in the [Deployment Guide](deployment-guide.md#governed-exchange-rates-on-upgrade). These are the fixes.

### A build or deploy is refused for missing rates

The consolidation build (or `deploy.sh` step 5/5) fails with:

```
konsolidat#93 refused before anything was deleted: N translated key(s) without a usable governed rate
(konsol Group Exchange Rate): JPY->USD FY2026 P3 missing; ...
```

Nothing was deleted: the consolidated trial balance keeps its last figures. For each key:

| Reason | Fix |
|--------|-----|
| `missing` | In konsol, open **Group Exchange Rate**, use **Pre-fill from ERP** for the period or enter the Closing and Average rates, and have the Close Lead submit (approve) them |
| `duplicate` | Cancel the extra approved rate |
| `invalid` or `implausible` | Cancel the rate and amend it with the right quote and Quoted Per |

Then run the build again. The message lists the first 50 keys. For all of them, run `dbt test --select assert_every_translated_currency_has_a_governed_rate`, or `dbt compile --select fx_governed_rate_gaps` for standalone SQL to run in `clickhouse-client`.

### `bench migrate` stops in the rate adoption

On an upgrade, the one-time rate adoption refuses to adopt a rate for a currency with no magnitude reference, and stops the migrate (and a deploy's step 3/5) with a message naming each currency:

```
konsol#103 adoption: no magnitude reference (ISO Currency usd_log10) for XYZ, which the adoption
would enter; every such rate would be refused. Create or edit ISO Currency XYZ, set USD Reference (log10).
Then rerun `bench migrate` ...
```

1. Set **USD Reference (log10)** on each named currency to roughly the log10 of its units per 1 USD: 3,500 per USD is log10(3,500) ≈ 3.54. Use 0.001 for a currency pegged 1:1 to the dollar.
    - If Desk shows the field, open **ISO Currency** `XYZ` (create it if it does not exist) and set it there.
    - During a deploy, the migrate stops at step 3/5, before step 4/5 recreates the application services. The backend still running is the old release, and its Desk may not show the field. Set it from the checkout directory instead, one command per currency:

        ```bash
        docker compose exec frappe_backend \
          bench --site <site> execute frappe.db.set_value --args '["ISO Currency", "XYZ", "usd_log10", 3.54]'
        ```

        This writes the column directly and commits. It fails loudly if the column does not exist, where `frappe.client.set_value` could skip a field the old release doesn't know.
2. Re-run `bench --site <site> migrate`, or `./deploy.sh`.

If the message says instead that the adoption **could not read the warehouse**, ClickHouse was not reachable. Start it and run the command the message prints: `bench --site <site> execute konsol.group_rates.adopt_erp_rates`. Add `--kwargs "{'dry_run': 1}"` to preview what it would adopt.

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
