# Decision: ClickHouse cluster mode (konsolidat #57)

**Issue:** grynn-in/konsolidat#57 · **Status:** next-round infra (P3, scale-gated)

## Context
Scaffolding for a clustered ClickHouse (Keeper + shards/replicas) exists (#56/#100)
but isn't functional end-to-end. Today runs single-node, which is fine for the
current data volume (~0.5M GL rows) and dev/demo/single-tenant use.

## Options
### A. Keeper + shards/replicas (self-managed HA)
Make the cluster config functional: ClickHouse Keeper, replicated MergeTree,
distributed tables.
- **+** HA + horizontal scale, self-hosted.
- **−** Real operational complexity (Keeper quorum, replication, `ON CLUSTER` DDL, rebalancing). dbt models need `ReplicatedMergeTree`/`Distributed` awareness. Big lift for no current need.

### B. Managed ClickHouse (ClickHouse Cloud / Altinity)
- **+** HA/scale without operating Keeper; least ops.
- **−** Cost; data residency; egress. Migration effort.

### C. Stay single-node + backups (status quo)
- **+** Simplest; matches current scale; already works.
- **−** No HA; vertical-scale ceiling.

## Recommendation
**C for now** (single-node + backups) — the data volume and single-tenant posture
don't justify a cluster, and premature clustering complicates every dbt model.
**When scale/HA genuinely lands**, prefer **B (managed)** unless self-hosting is a
hard requirement, in which case **A**. Decide together with #90 (prod infra) — the
two are the same "go to real production" milestone.

## Consequences
- Keep the cluster scaffolding dormant but don't invest further until a concrete scale/HA trigger.
- Ensure dbt model configs stay cluster-portable (the `cluster_engine()`/`cluster_name()` macros already abstract this).
