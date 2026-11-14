---
title: "Decision: Productionize Airbyte (konsolidat #90)"
sidebar_label: "#90 Productionize Airbyte"
description: Decision brief from the 2026-07-01 triage on moving Airbyte off the local abctl/kind install, with its status as of 2026-11-05 (unchanged).
---

# Decision: Productionize Airbyte (konsolidat #90)

**Issue:** grynn-in/konsolidat#90 · **Status (2026-07-01):** next-round infra (P2, not blocking)

:::note Provenance
Written for the 2026-07-01 open-issue triage (konsolidat `1ccafa9`, 2 July 2026). A recommendation; it names no decider. Text below is verbatim. The section "Status as of 2026-11-05" was added when the page was ported.
:::

## Context
Ingestion currently runs on a **local `abctl`/kind** Airbyte — fine for dev/demo,
but not a durable production posture (kind-in-container, manual connector loading,
no managed lifecycle/upgrades/secrets). The custom `source-d365-fno` connector is
loaded into that local kind.

## Options
### A. Airbyte via Helm on real Kubernetes
Deploy Airbyte OSS with the official Helm chart on a managed cluster; push the
custom connector to a registry.
- **+** Supported, upgradable, scalable; standard ops.
- **−** Requires a k8s cluster + registry; operational overhead; still self-hosting Airbyte.

### B. Airbyte Cloud
Managed SaaS.
- **+** Zero infra ops.
- **−** Custom D365 connector support/hosting on Cloud is constrained; data leaves the perimeter (may be unacceptable for finance data); recurring cost.

### C. Drop Airbyte for a lighter ingestion runner
Run the custom connector directly (or via `dlt`/Meltano) on a scheduled job into
ClickHouse, skipping the Airbyte control plane.
- **+** Far less moving infra; the value here is really just the one D365 connector + a couple of others.
- **−** Loses Airbyte's connector ecosystem + UI/state management; more bespoke code to own.

### D. Harden the current abctl setup
- **−** Polishing kind-in-container is a dead end for real prod.

## Recommendation
Defer (not blocking while dev runs locally). When it's time, evaluate **A vs C by
connector count**: if you need Airbyte's ecosystem (many ERPs/SaaS sources) →
**A (Helm on k8s)**; if it stays a handful of bespoke connectors → **C (a light
scheduled runner)** is dramatically less to operate. Avoid B for finance data.
Sequence alongside the broader prod-infra work (#57 CH).

## Consequences
- The A-vs-C call hinges on the multi-ERP roadmap (see the multi-erp-consolidation design doc); decide connector strategy first.

## Status as of 2026-11-05

**Unchanged: still abctl/kind.** No option has been taken.

| Fact | Evidence |
|---|---|
| `scripts/setup-airbyte.sh` installs Airbyte with `abctl local install` into its own kind cluster and attaches the kind node container to the `open_epm` Docker network; ClickHouse has a pinned IP (`172.30.0.10`) so Airbyte pods can reach it. | `scripts/setup-airbyte.sh:3-55`; `docker-compose.yml:116-117` |
| The Connector doctype registers six `erp_type` values (`d365_fo, d365_bc, sap_s4, sap_ecc, sap_b1, erpnext`) with an Airbyte source name each, but only the D365 F&O connector has an adapter in dbt besides ERPNext. The connector count the brief says should decide A vs C is therefore still small. | `connector.py` `_AIRBYTE_SOURCE`; `dbt_project/models/staging/` |
| Connector health is monitored from konsol (`refresh_connector_health` every 5 minutes; Airbyte webhook `airbyte_sync_complete`). | `hooks.py:112-114`; `api.py` |

Related: [Multi-ERP consolidation](https://docs.konsolidat.com/developer-guide/design/multi-erp-consolidation), [Deployment guide](https://docs.konsolidat.com/admin-guide/deployment-guide). Whether the GitHub issue is open was not checked from this machine.
