# Troubleshooting

Symptom-based debugging guide for Open EPM.

## Excel / VBA Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| All EPM cells show `0` | Cache empty, not refreshed | Press **Ctrl+Shift+R** |
| EPM cells show `0` after refresh | No data for the queried dimensions | Verify entity, year, period, account exist in ClickHouse |
| `#VALUE!` error in EPM cell | Wrong parameter types | Entity and account must be strings (in quotes); year must be numeric |
| `#NAME?` error | VBA module not loaded | Import `OpenEPM.bas` via Alt+F11 → File → Import |
| "Compile error: User-defined type not defined" | Missing VBA reference | Add `Microsoft Scripting Runtime` and `Microsoft XML, v6.0` in Tools → References |
| Refresh does nothing | No EPM formulas found | Check cells contain `=EPM(`, `=EPM_BUDGET(`, etc. (exact prefix match) |
| "Object variable or With block not set" | Cache not initialized | Close and reopen the workbook, or run `EPM_ClearCache` |
| Login prompt keeps appearing | Session expired or auth failed | Check Frappe credentials; verify Frappe is running on the configured URL |
| "Run-time error '429'" | XMLHTTP object creation failed | Ensure `Microsoft XML, v6.0` reference is enabled |
| Ctrl+Shift+R doesn't work | Key binding not active | Close/reopen workbook (binding is set in `Workbook_Open`) |
| Slow refresh (>30s) | Large number of unique query groups | Reduce variation in measure/scenario/period combos; use period ranges |

### Diagnostics

Run **EPM_Debug** (Alt+F8 → EPM_Debug) to test:
1. Cache initialization
2. HTTP object creation
3. Health endpoint connectivity
4. Formula scanning
5. Test batch query

Enable detailed logging with **EPM_ToggleLog** — check the `_EPM_Log` sheet for HTTP request/response details.

## API Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| `401 Unauthorized` | Not logged in | Call `POST /api/method/login` first |
| `403 Forbidden` | User lacks permission | Check Frappe user roles |
| `Invalid scenario: X` | Typo in scenario name | Use exactly: `actuals`, `budget`, or `variance` |
| `Measure X not allowed for scenario Y` | Wrong measure/scenario combo | Check [allowed measures](../api-reference/api-overview.md) |
| `Batch size N exceeds maximum of 2000` | Too many items | Split into multiple requests |
| `ClickHouse query timeout` | Query took >30s | Check ClickHouse health; optimize query dimensions |
| `ClickHouse connection failed` | ClickHouse unreachable | Verify ClickHouse is running; check EPM Settings |
| Empty `values` array (all zeros) | No matching data | Query ClickHouse directly to verify data exists |
| `null` values in response | Per-item validation error | Check the `errors` array in the response |

### Direct ClickHouse Verification

```bash
# Check if data exists for a specific query
curl "http://localhost:8123/?query=SELECT+count(*)+FROM+epm_gold.gold_trial_balance+WHERE+data_area_id='USMF'+AND+fiscal_year=2024+AND+fiscal_period=5"
```

## dbt Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| `dbt debug` fails | Bad profiles.yml | Check `~/.dbt/profiles.yml` — host, port, user, password |
| `Database epm_gold does not exist` | Init SQL not run | Run `clickhouse/init-db.sql` manually or restart the Docker container |
| Seed load fails | Column type mismatch | Check `dbt_project.yml` column_types config for the seed |
| Model build fails with ClickHouse error | SQL syntax issue | Check ClickHouse-specific syntax; use adapter macros |
| Test failures on fresh build | Expected — data-dependent | `warn`-severity tests may fail without D365 data; `error`-severity tests should pass |
| `Compilation Error: 'ref' not found` | Missing dependency | Run `dbt deps` to install packages |
| `Runtime Error: relation does not exist` | Upstream model not built | Run `dbt build` (not just `dbt run --select one_model`) |

### Rebuilding from Scratch

```bash
dbt build --full-refresh    # Drop all tables and rebuild
```

## ClickHouse Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| Container unhealthy | Startup failure | `docker logs open_epm_clickhouse` |
| Port 8123 not responding | Container not running | `docker compose up -d` |
| "Code: 60. DB::Exception: Table doesn't exist" | Tables not created | Run `dbt build` to create models |
| Slow queries | Large table scans | Check ORDER BY keys match query filters |
| Disk full | Data growth | Check sizes with `SELECT database, formatReadableSize(sum(bytes_on_disk)) FROM system.parts WHERE active GROUP BY database` |

## Frappe Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| `bench start` fails | Port 8069 in use | Kill the process: `fuser -k 8069/tcp` |
| "konsol app not installed" | App not linked | `bench --site your-site install-app konsol` |
| EPM Settings not found | DocType not created | Run `bench migrate` |
| API returns HTML instead of JSON | Wrong URL format | Use `/api/method/konsol.api.endpoint`, not `/konsol/api/endpoint` |
| "Not permitted" on EPM Settings | User lacks System Manager role | Grant the role in Frappe user settings |

## Airbyte Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| D365 sync returns 401 | Expired client secret | Rotate secret in Azure AD, update Airbyte source |
| Empty sync — 0 records | `cross_company` not enabled | Check stream settings in Airbyte |
| Sync stuck at "Running" | Timeout on large entity | Increase timeout; switch to incremental sync |
| ClickHouse destination error | Wrong credentials | Verify host, port, database in destination config |

## Pipeline (Task Pane) Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| Task pane shows blank | Frappe not running at manifest URL | Start Frappe on `http://localhost:8069` |
| Login fails in task pane | CORS or cookie issue | Check browser console; verify same-origin setup |
| Pipeline status stuck on "Queued" | Background worker not running | Check `bench start` includes workers |
| "Trigger Pipeline" does nothing | Pipeline Run doctype missing | Run `bench migrate` |

## Common Patterns

### "It was working yesterday"

1. Check ClickHouse: `docker ps` → healthy?
2. Check Frappe: `curl http://localhost:8069/api/method/konsol.api.health`
3. Check data freshness: When was the last Airbyte sync?
4. Check dbt: Was `dbt build` run after the latest sync?

### "Numbers look wrong"

1. Query ClickHouse directly to isolate API vs data issues
2. Check the period — is it 1-12 (month) or a range code (Q1, FY)?
3. Check the measure — is it the right one for the scenario?
4. Check dimensions — are cost_center/department filters narrowing results unexpectedly?
5. Run dbt tests: `dbt test` — any failures?

## Getting Help

- [FAQ](faq.md) — Common questions by audience
- [Monitoring](../admin-guide/monitoring.md) — System health checks
- [Operations Runbook](../admin-guide/operations-runbook.md) — Standard procedures
