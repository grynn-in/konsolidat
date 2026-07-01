# Decision: Productionize Airbyte (konsolidat #90)

**Issue:** grynn-in/konsolidat#90 · **Status:** next-round infra (P2, not blocking)

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
