# PRD: Production Hardening

**Status:** Not Started
**Date:** 2026-06-13
**Phase:** Phase 7 — Production Hardening
**Repos:** `konsolidat` (dbt/data stack, docker-compose, `deploy.sh`), `konsol` (Frappe app — API, scheduler, alerting)

## Problem

The stack runs in production (9 Docker services, one-click `deploy.sh`) but operational guarantees are manual or absent:

- **No off-site ClickHouse backup automation.** `./deploy.sh backup` writes to `./backups/` with 7-day rotation and a `BACKUP_S3_BUCKET` env stub exists, but nothing schedules a ClickHouse-native snapshot or verifies restorability. A volume loss = total loss of `epm_bronze/silver/gold`.
- **No metrics.** `monitoring.md` documents `system.query_log` queries and `konsol.api.health` to be run by hand. There is no Prometheus scrape, no Grafana dashboard, no historical CH query-latency or Frappe response-time series. Alert thresholds in `monitoring.md` (API > 2s warn / > 10s critical; CH > 5s / > 30s timeout; disk > 70% / > 90%) are defined but not enforced.
- **No alerting.** `dbt build` exit codes and Airbyte sync failures are checked ad-hoc. A failed monthly close (e.g. `assert_trial_balance_balances` error) produces no email/Slack notification — the controller finds out when Excel shows stale numbers.
- **No load validation.** Deployment targets 50 concurrent Excel users (`=EPM()` over ODBC :15432 + REST) but this has never been measured. CH query timeout is 30s; we don't know the p95 under load.
- **Runbooks are prose, not gated.** `operations-runbook.md` lists the monthly close steps but there is no enforced checklist or DR drill record.

## Solution

Add a self-hosted observability and reliability layer: scheduled, restore-verified ClickHouse backups to Azure Blob/S3; Prometheus + Grafana scraping CH and Frappe metrics; a Frappe-driven alerting hook that fires email/Slack on pipeline/dbt/backup failure; a k6 load test for 50 concurrent Excel users; and codified monthly-close + DR runbooks with measurable acceptance.

## Scope

### 1. ClickHouse Backup Automation

Use [`clickhouse-backup`](https://github.com/Altinity/clickhouse-backup) (already named in `operations-runbook.md` scheduled tasks) as a sidecar container in `docker-compose.yml`.

| Setting | Value |
|---|---|
| Schedule | Nightly 01:00 (before existing 02:00 Frappe backup) |
| Databases | `epm_bronze`, `epm_silver`, `epm_gold`, plus `epm_staging` if present |
| Remote storage | Azure Blob (`remote_storage: azblob`) or S3 (`remote_storage: s3`), selected by env |
| Retention | 7 daily local, 30 daily remote |
| Env (extend `.env`) | `CLICKHOUSE_BACKUP_REMOTE` (`azblob`\|`s3`), `AZBLOB_ACCOUNT`/`AZBLOB_KEY`/`AZBLOB_CONTAINER`, `BACKUP_S3_BUCKET` (reuse existing) |

- New `deploy.sh ch-backup` subcommand wraps `clickhouse-backup create_remote` + local prune.
- Nightly **restore verification**: weekly cron restores latest remote backup into a throwaway `epm_gold_verify` DB and asserts `count(*) > 0` on `gold_trial_balance`; emits alert on failure.

### 2. Monitoring — Prometheus + Grafana

Add `prometheus` and `grafana` services to `docker-compose.yml` on the internal Docker network (no public host ports; reached via Caddy `/grafana` reverse-proxy path, consistent with Phase 4 isolation).

| Target | Exporter / Endpoint | Key metrics |
|---|---|---|
| ClickHouse | Native `/metrics` (enable `prometheus` in CH config) + `system.query_log` exporter | query latency (p50/p95/p99), `read_rows`, failed queries, `bytes_on_disk` per `epm_*` DB, active `system.processes` |
| Frappe / Konsol | New `konsol.api.metrics` Prometheus endpoint (Guest-readable, mirrors `konsol.api.health`) | HTTP request duration histogram, RQ worker queue depth, scheduler heartbeat age |
| Host / Docker | `node_exporter` + `cadvisor` | disk usage %, RAM, per-container CPU |

- Grafana dashboard **"Konsolidat Ops"**: panels for CH query p95, Frappe API p95, CH disk %, dbt last-build status, last-backup age, Airbyte last-sync status.
- Provision dashboard + datasource as code (`monitoring/grafana/provisioning/`) so it survives redeploy.

### 3. Alerting — Email / Slack

Implement in `konsol` so it reuses existing Frappe credentials and the Pipeline Run record, rather than Prometheus Alertmanager for app-level events. Use Prometheus Alertmanager only for infra metrics (disk, CH down).

| Trigger | Source | Channel |
|---|---|---|
| dbt test failure (`error` severity) | Pipeline runner parses `dbt build` JSON exit | Email + Slack |
| dbt `warn` severity | same | Slack only |
| Pipeline Run status = Failed | `konsol` Pipeline Run doctype state change hook | Email + Slack |
| Airbyte sync failure | Pipeline runner / sync poller | Email + Slack |
| ClickHouse backup or restore-verify failure | §1 cron exit code | Email + Slack |
| Infra: CH disk > 90%, CH down, Frappe API p95 > 10s | Alertmanager rules from §2 thresholds | Slack |

- New `Alert Settings` single doctype: `slack_webhook_url`, `alert_email_recipients` (comma list), `enable_email`, `enable_slack`, per-trigger severity floor.
- Reuse Frappe email queue for email; POST to Slack incoming webhook for Slack. Alert payload includes Pipeline Run name, failed test list, and a direct Desk link.
- Critical dbt tests that MUST alert (from `operations-runbook.md`): `assert_trial_balance_balances`, `assert_silver_gl_debit_credit_balance`, `assert_spread_sums_to_annual`, `assert_ic_elimination_nets_zero`, `assert_fctb_entity_layer_ties`.

### 4. Load Testing — 50 Concurrent Excel Users

k6 script in `load-test/` modeling the real Excel access pattern.

| Param | Value |
|---|---|
| Virtual users | 50 concurrent, 5-min ramp, 15-min steady |
| Mix | 70% `=EPM()` reads (REST `konsol.api.epm_value` + ODBC :15432 `epm_gold` queries), 20% `EPM_RefreshAll` bursts (10–30 cells/sheet), 10% `EPMSAVE()` budget write-back |
| Auth | Frappe session cookie (login once per VU, as VBA/Office.js does) |
| Pass thresholds | API read p95 < 2s, CH query p95 < 5s, error rate < 1%, zero CH 30s timeouts |

- Run against a medium-sized dataset (10–50 entities per `deployment-guide.md` sizing) on the target prod spec (4 vCPU / 16 GB).
- Output feeds Grafana via a one-shot Prometheus push; record results in DR/perf section of runbook.

### 5. Monthly Close Runbook (codified)

Promote `operations-runbook.md` "Monthly Close Procedure" into a gated checklist with verification commands and expected outputs:

1. Trigger Airbyte sync → confirm sync `succeeded` (alert if not).
2. `dbt build` → all models + tests pass; the 5 critical tests in §3 must be green.
3. Verify consolidation: CTA non-zero where FX differs, IC eliminations net zero, NCI split correct.
4. `EPM_ClearCache` → `EPM_RefreshAll` in Excel.
5. Sign-off recorded in a `Close Run` log (date, operator, dbt test count pass/fail, anomalies).

### 6. Disaster Recovery Procedure

Documented + drillable RTO/RPO targets and a restore script path.

| Target | Value |
|---|---|
| RPO | 24h (nightly remote backup) |
| RTO | 2h on fresh server |
| Procedure | `git clone && ./deploy.sh` → `./deploy.sh restore --from <remote>` (MariaDB + ClickHouse + Frappe files) → run §5 verification |

- Quarterly DR drill: restore latest remote backup onto a scratch server, run monthly-close verification, record elapsed time vs RTO.

## Out of Scope

- Multi-node / sharded ClickHouse cluster and HA failover (tracked under Phase 3 Scale Architecture).
- Entra ID SSO, Caddy rate limiting, ClickHouse network isolation (Phase 4 — referenced only where it gates dashboard exposure).
- Application performance refactoring (query/index tuning) beyond what load-test thresholds reveal.
- Per-connector health dashboard for non-D365 ERPs (Phase 3).
- Log aggregation stack (Loki/ELK) — file logs in `~/frappe-bench/logs/` remain the source of truth.

## Acceptance Criteria

1. A scheduled `clickhouse-backup` run produces a remote backup in Azure Blob/S3 nightly; `clickhouse-backup list remote` shows ≤ 30 entries with the newest < 24h old.
2. Weekly restore-verify restores into `epm_gold_verify` and `SELECT count(*) FROM epm_gold_verify.gold_trial_balance` returns > 0; failure fires an alert.
3. Grafana "Konsolidat Ops" dashboard renders CH query p95, Frappe API p95, CH disk %, last-backup age, and dbt last-build status from live Prometheus data after a clean `./deploy.sh`.
4. `konsol.api.metrics` returns HTTP 200 in Prometheus exposition format and is scraped successfully (target `UP` in Prometheus).
5. Forcing a dbt test to error (e.g. break `assert_trial_balance_balances`) during a Pipeline Run sends both an email and a Slack message naming the failed test and Pipeline Run.
6. A Pipeline Run ending in `Failed` triggers an alert per `Alert Settings`; disabling a channel in `Alert Settings` suppresses only that channel.
7. k6 load test at 50 VUs meets all §4 thresholds (API p95 < 2s, CH p95 < 5s, error rate < 1%, zero 30s timeouts); results archived.
8. DR drill on a fresh server completes `clone → deploy → restore → §5 verification` within the 2h RTO, with `assert_trial_balance_balances` passing on restored data.
9. Monthly close produces a `Close Run` record with pass/fail test counts; an open critical-test failure blocks sign-off.

## Open Questions

- Azure Blob vs S3 as the default remote backend, or support both via the `CLICKHOUSE_BACKUP_REMOTE` switch from day one?
- Should infra alerts route through Alertmanager → Slack, or also funnel through `Alert Settings` for a single notification surface?
- Does `konsol.api.metrics` expose per-method Frappe latency, or do we rely on a Frappe-level WSGI middleware exporter for request timing?
- Load-test environment: dedicated staging server vs. a maintenance-window run against production?
