---
title: "Decision: ClickHouse cluster mode (konsolidat #57)"
sidebar_label: "#57 ClickHouse cluster mode"
description: Decision brief from the 2026-07-01 triage on when to run ClickHouse as a cluster, with its status as of 2026-11-05 (still single-node).
---

# Decision: ClickHouse cluster mode (konsolidat #57)

**Issue:** grynn-in/konsolidat#57 · **Status (2026-07-01):** next-round infra (P3, scale-gated)

:::note Provenance
Written for the 2026-07-01 open-issue triage (konsolidat `1ccafa9`, 2 July 2026). A recommendation; it names no decider. Text below is verbatim. The section "Status as of 2026-11-05" was added when the page was ported.
:::

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

## Status as of 2026-11-05

**Unchanged: single-node.** The scaffolding is still dormant and still unverified on a real cluster.

| Fact | Evidence |
|---|---|
| Cluster files exist and have not changed since June: `docker-compose.cluster.yml`, `clickhouse/cluster/{remote_servers.xml, keeper.xml, macros-shard{1,2,3}-replica1.xml}`, the `cluster` target in `dbt_project/profiles.yml` (marked NEEDS-A-CLUSTER), `dbt_project/macros/cluster.sql`. | `git log -- docs/admin-guide/cluster-setup.md` last touched `721b6f3` (2026-06-18); file listing |
| 11 models call `cluster_engine()` / `cluster_name()` (3 bronze, 8 gold), up from the 3 the June guide lists. With `cluster_enabled: false` (the default in `dbt_project.yml:57`) they compile exactly as before. | `grep -l cluster_engine dbt_project/models` |
| Production ingestion is still the local `abctl`/kind Airbyte, so the "go to real production" milestone this brief ties itself to has not been reached either (see [konsolidat #90](konsolidat-90-airbyte-prod.md)). | `scripts/setup-airbyte.sh` |

Setup procedure: [ClickHouse cluster setup](https://docs.konsolidat.com/admin-guide/cluster-setup). Whether the GitHub issue is open was not checked from this machine.
