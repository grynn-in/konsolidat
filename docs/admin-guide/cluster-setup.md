# ClickHouse Cluster Setup Guide (Scale Architecture §2)

> **Status: BUILD-ONLY — NEEDS CLUSTER VERIFICATION**
>
> The cluster macros, config files, and dbt changes are implemented and `dbt parse`
> passes with the single-node default unchanged.  End-to-end cluster correctness
> (Distributed reads, cross-shard consolidation, all 144 dbt tests in cluster mode)
> has **NOT** been verified — a real multi-node ClickHouse + Keeper setup is
> required.  This guide describes the expected setup procedure.
>
> Issue: [grynn-in/konsolidat#53](https://github.com/grynn-in/konsolidat/issues/53)

## Overview

Konsolidat shards the ClickHouse warehouse by `entity_id` across a
`konsol_cluster` cluster using `Distributed` + `ReplicatedMergeTree`.  A given
legal entity's rows colocate on one shard (`cityHash64(entity_id)`), so per-LE
GL history queries avoid cross-shard scatter for common single-entity reports.

| Item | Value |
|------|-------|
| Cluster name | `konsol_cluster` |
| Shard key | `cityHash64(entity_id)` |
| Local table engine | `ReplicatedMergeTree` (ZK path `/clickhouse/tables/{shard}/{database}/{table}`) |
| Query table engine | `Distributed(konsol_cluster, <db>, <local_table>, cityHash64(entity_id))` |
| Coordinator | ClickHouse Keeper (co-located or standalone quorum) |
| Sharded databases | `epm_bronze`, `epm_silver`, `epm_gold` |

Single-node remains the default; cluster mode is **opt-in** via:

```bash
dbt build --target cluster --vars '{"cluster_enabled": true}'
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ API / Cube.js / dbt tests                                        │
│          ↓ SELECT from Distributed table                         │
├──────────────────┬──────────────────┬──────────────────────────┤
│  ch-shard1       │  ch-shard2       │  ch-shard3               │
│  ReplicatedMT    │  ReplicatedMT    │  ReplicatedMT            │
│  _local tables   │  _local tables   │  _local tables           │
│  (entity_id A-D) │  (entity_id E-K) │  (entity_id L-Z)         │
├──────────────────┴──────────────────┴──────────────────────────┤
│ ClickHouse Keeper quorum (consensus / replication coordination)  │
└─────────────────────────────────────────────────────────────────┘
```

## Prerequisites

- 3 (or more) hosts / VMs with Docker and Docker Compose v2.
- A private network between the hosts (all nodes reachable by hostname).
- Shared `CLICKHOUSE_PASSWORD` secret.
- dbt-clickhouse ≥ 1.6.0 (`cluster` config key support).

## Step 1 — Generate per-node macros files

Each ClickHouse node needs a `macros.xml` with its `{shard}` and `{replica}`
values so ClickHouse can expand them in ReplicatedMergeTree ZK paths.

```bash
# Helper: generate macros XML for a given shard/replica combination
for shard in 1 2 3; do
  cat > clickhouse/cluster/macros-shard${shard}-replica1.xml <<EOF
<clickhouse>
  <macros>
    <shard>0${shard}</shard>
    <replica>replica1</replica>
    <cluster>konsol_cluster</cluster>
  </macros>
</clickhouse>
EOF
done
```

A pre-generated example for shard 1 replica 1 is at
`clickhouse/cluster/macros-shard1-replica1.xml`.

## Step 2 — Update remote_servers.xml

Edit `clickhouse/cluster/remote_servers.xml` and replace the placeholder
hostnames (`ch-shard1`, `ch-shard2`, `ch-shard3`) with the real IPs or DNS
names of your three nodes.

## Step 3 — Start the cluster

On **each** of the three nodes, set the node-specific environment and start:

```bash
# On node 1
export SHARD_ID=1
export REPLICA_ID=1
export CH_HOST_1=<ip-of-node1>
export CH_HOST_2=<ip-of-node2>
export CH_HOST_3=<ip-of-node3>
export CLICKHOUSE_PASSWORD=<shared-secret>

docker compose -f docker-compose.cluster.yml up -d
```

Repeat with `SHARD_ID=2` on node 2 and `SHARD_ID=3` on node 3.

Wait for all three healthchecks to pass:

```bash
docker compose -f docker-compose.cluster.yml ps
```

## Step 4 — Initialise databases ON CLUSTER

Run the init script through the cluster so all nodes create the databases:

```bash
docker compose -f docker-compose.cluster.yml exec clickhouse \
  clickhouse-client -q "CREATE DATABASE IF NOT EXISTS epm_bronze ON CLUSTER konsol_cluster"
docker compose -f docker-compose.cluster.yml exec clickhouse \
  clickhouse-client -q "CREATE DATABASE IF NOT EXISTS epm_silver ON CLUSTER konsol_cluster"
docker compose -f docker-compose.cluster.yml exec clickhouse \
  clickhouse-client -q "CREATE DATABASE IF NOT EXISTS epm_gold   ON CLUSTER konsol_cluster"
docker compose -f docker-compose.cluster.yml exec clickhouse \
  clickhouse-client -q "CREATE DATABASE IF NOT EXISTS epm_staging ON CLUSTER konsol_cluster"
```

Also run the staging init script:

```bash
docker compose -f docker-compose.cluster.yml exec clickhouse \
  clickhouse-client --multiquery < clickhouse/init-db.sql
```

## Step 5 — Set environment and run dbt in cluster mode

```bash
export CLICKHOUSE_HOST=<ip-of-any-node>
export CLICKHOUSE_PORT=8443
export CLICKHOUSE_USER=default
export CLICKHOUSE_PASSWORD=<shared-secret>
export DBT_TARGET=cluster

cd dbt_project

# Build all models with cluster engines + ON CLUSTER DDL
dbt build --target cluster --vars '{"cluster_enabled": true}'
```

This builds every opted-in model with `ReplicatedMergeTree` ON CLUSTER.
Tables are named `<model>_local` by the convention established in the macros.

## Step 6 — Create Distributed overlay tables

After the `_local` ReplicatedMergeTree tables exist on all shards, create
the unsuffixed `Distributed` tables that the API and Cube.js query:

```bash
dbt run-operation create_distributed_tables \
  --vars '{"cluster_enabled": true}'
```

This generates and executes DDL of the form:

```sql
CREATE TABLE IF NOT EXISTS epm_bronze.bronze_general_journal_account_entries
ON CLUSTER konsol_cluster
AS epm_bronze.bronze_general_journal_account_entries_local
ENGINE = Distributed(
  'konsol_cluster',
  'epm_bronze',
  'bronze_general_journal_account_entries_local',
  cityHash64(entity_id)
);
```

## Step 7 — Verify

```bash
# Check shards are online
clickhouse-client -q "SELECT * FROM system.clusters WHERE cluster = 'konsol_cluster'"

# Confirm entity rows colocate (one row per entity_id per shard)
clickhouse-client -q "
  SELECT shardNum(), count() as row_count
  FROM epm_gold.gold_trial_balance
  WHERE data_area_id = 'USSI'
  GROUP BY shardNum()
"
# Expected: exactly ONE shard returns a non-zero count.

# Distributed count matches single-node baseline
clickhouse-client -q "
  SELECT count(distinct data_area_id) FROM epm_gold.gold_trial_balance
"
```

Run the full dbt test suite against the cluster:

```bash
dbt test --target cluster --vars '{"cluster_enabled": true}'
```

**NEEDS-A-CLUSTER**: All 144 dbt tests must pass in cluster mode before this
is considered production-ready.

## Model opt-in

Not all models need to be cluster-aware immediately.  To opt a model in:

1. Replace the hardcoded `engine` and add `cluster` in its `config()`:

```sql
-- Before
{{
    config(
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

-- After (cluster-aware)
{{
    config(
        engine=cluster_engine('MergeTree()'),
        order_by='tuple()',
        cluster=cluster_name()
    )
}}
```

2. The SELECT query body is **never changed**.

3. When `cluster_enabled=false` (default), `cluster_engine()` returns the
   original string and `cluster_name()` returns `none` → compiled SQL is
   identical to before.

Already opted-in models (examples in this PR):

- `bronze_general_journal_account_entries`
- `bronze_general_journal_entries`
- `gold_trial_balance`

## Configuration files

| File | Purpose |
|------|---------|
| `clickhouse/cluster/remote_servers.xml` | Cluster topology (shard hosts) |
| `clickhouse/cluster/keeper.xml` | ClickHouse Keeper (raft + ZK compat) |
| `clickhouse/cluster/macros-shard1-replica1.xml` | Per-node `{shard}` / `{replica}` macros |
| `docker-compose.cluster.yml` | Docker Compose overlay for 3-node cluster |
| `dbt_project/profiles.yml` (cluster target) | dbt cluster target with `cluster: konsol_cluster` |
| `dbt_project/macros/cluster.sql` | Opt-in cluster macros |

## Open questions

These items are NOT resolved in this PR and require cluster-level testing
before GA:

### Hot-shard risk

`cityHash64(entity_id)` distributes entities evenly by hash, but a single
very large LE (e.g. one entity with 10 years of daily GL history) may
concentrate row volume on one shard.

**Options to evaluate on a real cluster:**

- Composite shard key: `cityHash64(concat(entity_id, toString(fiscal_year)))` —
  fans out one LE across shards by year; breaks per-LE colocality for some
  queries.
- Oversized-LE detection: monitor `system.parts` per shard; flag entities where
  `sum(rows)` on a single shard exceeds 3× the mean.
- Per-LE manual routing: route known large LEs to dedicated shards via custom
  `sharding_key` expressions or separate databases.

### Rebalancing

When a new legal entity is onboarded after initial sharding, `cityHash64`
routes it deterministically — no explicit rebalancing is needed.  However,
if an existing LE grows disproportionately, resharding requires:

1. Creating a new cluster topology.
2. Copying data using `INSERT INTO new_table SELECT * FROM old_table`.
3. Swapping Distributed table definitions.

This is operationally expensive.  Decide on acceptable skew tolerance before
GA.  A `max_rows_to_read` limit per shard query can mitigate hot-shard
query timeouts in the interim.

### Cross-shard aggregation correctness

Gold models that aggregate across entities (`gold_trial_balance`,
`gold_consolidated_trial_balance`, IC eliminations, NCI movement) perform
cross-shard reads through the Distributed engine.  ClickHouse pushes
aggregation to each shard first then combines results at the coordinator.

Points to verify on a real cluster:

- `GLOBAL IN` / `GLOBAL JOIN` for cross-shard subqueries (ClickHouse does
  not automatically promote IN to GLOBAL IN for Distributed reads).
- `sum()` / `count()` aggregations across shards are additive — verify totals
  match the single-node baseline.
- `asof left join` in `gold_consolidated_trial_balance` and temporal ownership
  joins may behave differently under Distributed read semantics.

### Cube.js pre-aggregation

Cube.js schema files point at `epm_gold.<table>` which will be the Distributed
table after Step 6.  Pre-aggregation may need a shard-aware refresh key or
pre-agg tables collocated per-shard to avoid cross-shard materialisation.
Evaluate before enabling pre-aggregations in cluster mode.
