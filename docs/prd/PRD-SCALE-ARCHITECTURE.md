# PRD: Scale Architecture (50–500 Legal Entities)

**Status:** Not Started
**Date:** 2026-06-13
**Phase:** Phase 3 — Multi-ERP Support (Scale Architecture)
**Repos:** `konsolidat` (dbt/data stack, ClickHouse, Airbyte), `konsol` (Frappe app — orchestration + monitoring API/Desk)

## Problem

- The pipeline is validated against a handful of D365 F&O legal entities. At 50–500 LEs across SAP, D365 F&O, D365 BC, and ERPNext, today's full-refresh extraction is untenable: Airbyte re-pulls `GeneralJournalAccountEntryBiEntities` and equivalents in full every sync, so extraction time and ClickHouse write load grow linearly with entity count and history depth.
- Bronze partitioning is done (`bronze_general_journal_account_entries` by `toYear(accounting_date)`, budget by `toYYYYMM(transaction_date)`, FX by `toYear(valid_from)`) and per-ERP dbt builds already run in parallel via the adapter pattern (`var('erp_sources')` drives the canonical UNION ALL in `stg_gl_entries.sql`). But the remaining three scale items are open: incremental extraction, a sharded ClickHouse cluster, and per-connector health monitoring.
- A single-node ClickHouse cannot hold 500-LE GL history with acceptable query latency; the canonical grain carries `entity_id` and `erp_source` (see `models/staging/canonical/stg_gl_entries.sql`) but nothing shards on it.
- Monitoring (`docs/admin-guide/monitoring.md`) lists "Airbyte sync failure → Critical" as an alert threshold, but there is no per-connector surface in Frappe — operators cannot see which of N connectors is stale, failing, or lagging.

## Solution

Make extraction incremental (Airbyte CDC / cursor-based for high-volume ERPs), shard the ClickHouse warehouse by `entity_id` across a cluster using `Distributed` + `ReplicatedMergeTree`, and expose a per-connector health dashboard in Frappe Desk backed by a `Connector Health` doctype synced from Airbyte and ClickHouse `system` tables.

## Scope

### 1. Incremental Extraction (Airbyte CDC / cursor)

Per-connector sync mode, replacing full-refresh for high-volume GL streams. Cursor and primary key per the canonical contract (`record_id` → `_raw_id`, `_loaded_at`).

| Connector | ERP | Sync mode | Cursor field | Primary key |
|-----------|-----|-----------|--------------|-------------|
| D365 F&O | `d365_fo` | Incremental — cursor | `ModifiedDateTime` | `RecId` |
| SAP S/4HANA | `sap_s4` | Incremental — cursor (CDS delta token) | `LastChangeDateTime` | `JournalEntry` + `LedgerGLLineItem` |
| SAP ECC 6.0 | `sap_ecc` | Incremental — CDC (log-based where available) | `CPUDT`/`AEDAT` | `BUKRS`+`BELNR`+`GJAHR`+`BUZEI` |
| D365 BC | `d365_bc` | Incremental — cursor | `lastModifiedDateTime` | `systemId` |
| ERPNext | `erpnext` | Incremental — cursor | `modified` | `name` |

- Bronze remains `INSERT`-with-dedup: bronze tables stay `ReplacingMergeTree` keyed on `(_raw_id)` ordered by `_loaded_at` so re-delivered rows from CDC collapse to latest.
- High-volume streams (GL line items, GL headers) are incremental; low-volume masters (legal entities, accounts, dimensions, FX, fiscal calendar) may stay full-refresh.
- dbt bronze/silver models that consume incremental sources must declare `materialized='incremental'` with `incremental_strategy` filtering on `_loaded_at > (select max(_loaded_at) from {{ this }})` so only new CDC deltas reprocess. Affected first: `bronze_general_journal_account_entries`, `bronze_general_journal_entries`, `bronze_budget_transaction_lines`.

### 2. ClickHouse Cluster — Sharded by `entity_id`

Horizontal scale for 50–500 LEs. Shard key derived from the canonical `entity_id` so a given LE's rows colocate.

| Item | Value |
|------|-------|
| Cluster name | `konsol_cluster` (defined in `remote_servers` of cluster config) |
| Shard key | `cityHash64(entity_id)` |
| Engine (local tables) | `ReplicatedMergeTree` on each shard |
| Engine (query tables) | `Distributed(konsol_cluster, <db>, <local_table>, cityHash64(entity_id))` |
| Coordination | ClickHouse Keeper (replaces ZooKeeper) |
| Sharded databases | `epm_bronze`, `epm_silver`, `epm_gold` |

- Each existing partitioned table gets a `_local` ReplicatedMergeTree counterpart per shard; the unsuffixed name becomes the `Distributed` table the API and Cube.js query.
- Partition keys are preserved per shard (`toYear(accounting_date)` etc.) — sharding is orthogonal to partitioning.
- Cross-shard consolidation (FX translation, IC elimination, NCI) runs as `GLOBAL`-aware queries; gold models that aggregate across entities (`gold_trial_balance`, consolidation outputs) must be validated for correctness on `Distributed` reads.
- dbt targets the cluster via `cluster: konsol_cluster` in `profiles.yml`; `ON CLUSTER` DDL for replicated table creation.
- Single-node remains the default deploy; cluster mode is enabled by a profile/var so small installs are unaffected.

### 3. Per-Connector Health Dashboard (Frappe)

New `konsol` doctype + API + Desk dashboard. One row per active connector (from the Connector Registry, PRD 37).

**`Connector Health` doctype**

| Field | Type | Description |
|-------|------|-------------|
| `connector` | Link (Connector Registry) | ERP connector, e.g. `sap_s4` |
| `erp_source` | Data | Canonical `erp_source` value |
| `last_sync_start` | Datetime | From Airbyte job |
| `last_sync_end` | Datetime | From Airbyte job |
| `last_sync_status` | Select (Succeeded / Failed / Running / Stale) | Derived |
| `rows_emitted` | Int | Records in last sync |
| `sync_duration_s` | Int | `last_sync_end − last_sync_start` |
| `lag_minutes` | Int | `now() − last_sync_end` |
| `entities_loaded` | Int | `count(distinct entity_id)` for this `erp_source` in `epm_bronze` |
| `last_error` | Small Text | Airbyte failure message |

- API: `konsol.api.connector_health` (guest-restricted; role-gated to Controller/Admin) returns the full list as JSON; extends the existing health surface in `docs/admin-guide/monitoring.md`.
- Background job (Frappe scheduler) polls the Airbyte API + ClickHouse `system.parts`/`system.query_log` and upserts `Connector Health` rows; default interval 5 min.
- Desk dashboard: a Frappe Number Card per connector (green/amber/red on `last_sync_status` + `lag_minutes`) plus a list view.
- Alert: when `last_sync_status = Failed` or `lag_minutes` exceeds the connector's `refresh_frequency`, raise a Frappe Notification (matches monitoring.md "Airbyte sync failure → Critical").

## Out of Scope

- Building the connectors themselves (SAP, D365 BC, ERPNext) — covered by PRDs 32–36.
- Dimension Harmonization across ERPs — separate Phase 3 task.
- Connector Registry doctype definition — PRD 37 (this PRD only links to it).
- Prometheus/Grafana infra metrics and ClickHouse backup automation — Phase 7 (Production Hardening).
- Entra ID SSO / network isolation of the cluster — Phase 4.
- Cube.js semantic-layer changes beyond pointing at `Distributed` tables.

## Acceptance Criteria

1. With CDC enabled, a sync after an initial backfill transfers only changed rows: a controlled test that posts 100 GL lines to one LE results in an Airbyte incremental sync whose `rows_emitted` is on the order of 100, not the full table.
2. Re-delivered CDC rows do not duplicate: querying `bronze_general_journal_account_entries` for a known `_raw_id` returns exactly one active row after `OPTIMIZE ... FINAL` (ReplacingMergeTree dedup).
3. Incremental dbt run on bronze processes only new `_loaded_at` deltas — `dbt run --select bronze_general_journal_account_entries` on an unchanged source touches 0 rows.
4. On `konsol_cluster`, `SELECT count(distinct entity_id) FROM epm_gold.gold_trial_balance` returns the same total as the pre-cluster single-node baseline (no rows lost or double-counted across shards).
5. Rows for a single `entity_id` reside on exactly one shard: `SELECT shardNum(), count() FROM ... GROUP BY 1` for one LE returns a single shard.
6. All 144 existing dbt tests pass against the clustered warehouse (`dbt build` green in cluster mode).
7. `GET konsol.api.connector_health` returns one object per active connector, each with non-null `last_sync_status`, `lag_minutes`, and `entities_loaded`.
8. Stopping/failing one connector flips its `Connector Health.last_sync_status` to `Failed` within one scheduler cycle and fires a Frappe Notification; other connectors remain `Succeeded`.
9. Single-node deploy (cluster mode off) still passes the full-stack health check in `docs/admin-guide/monitoring.md` unchanged.

## Open Questions

- Shard key: `cityHash64(entity_id)` gives even distribution but a very large single LE could create a hot shard — do we need a composite key (e.g. `entity_id` + `fiscal_year`) for the largest tenants?
- SAP ECC log-based CDC depends on customer landscape (SLT vs. RFC polling); confirm whether ECC falls back to `AEDAT` cursor when log-based is unavailable.
- Rebalancing: when a new LE is onboarded after sharding, do we accept skew or run a periodic reshard? Decide tolerance before GA.
- Airbyte polling vs. webhook for `Connector Health` — does the deployed Airbyte version expose a job-status API stable enough to poll every 5 min, or do we tail Airbyte's own tables?
- Does Cube.js pre-aggregation need a shard-aware refresh key, or is querying the `Distributed` table sufficient at target volume?
