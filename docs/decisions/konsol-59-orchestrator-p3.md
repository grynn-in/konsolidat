---
title: "Decision: Orchestrator P3 (konsol #59)"
sidebar_label: "konsol #59 Orchestrator P3"
description: Decision brief from the 2026-07-01 triage on lineage, metrics, connection management and FX surfacing, with its status as of 2026-11-05.
---

# Decision: Orchestrator P3 (konsol #59)

**Issue:** grynn-in/konsol#59 · **Status (2026-07-01):** groundwork only — lowest priority

:::note Provenance
Written for the 2026-07-01 open-issue triage (konsolidat `1ccafa9`, 2 July 2026). A recommendation; it names no decider. Text below is verbatim. The section "Status as of 2026-11-05" was added when the page was ported.
:::

## Context
P3 = lineage/metrics, connection management, FX surfacing, multi-ERP. Groundwork
exists: `orchestrator/lineage.py`; multi-ERP has a merged consolidated fact +
design doc (konsolidat #126); FX surfacing is tracked in konsolidat #91.

## Options (which slice, if any, to pick up)
### A. FX surfacing + a basic lineage view (recommended slice)
Ship the read-only FX view (konsolidat #91 Part B) surfaced in the exec plane,
plus a minimal lineage/what-ran-produced-what view from `lineage.py`.
- **+** Both are read-only, high-signal, low-risk; FX surfacing is independently wanted.
- **−** Metrics dashboards + connection management deferred.

### B. Full P3
Lineage UI + metrics + connection management + multi-ERP UX all at once.
- **−** Large, low-urgency; most of it is polish on an already-working plane.

### C. Defer entirely
- **+** Focus effort on P2 (#58) and features (#93/#91).
- **−** Leaves lineage/metrics unshipped.

## Recommendation
**Lowest priority of the epic.** Do the **A slice** opportunistically — especially
FX surfacing, since konsolidat #91 Part B delivers the data-side and this just
exposes it in the plane. Everything else in P3 waits behind P2 (#58) and the
consolidation-currency feature (#93).

## Consequences
- Coordinate the FX-surfacing piece with konsolidat #91 (build the CH view once, consume it in both the report and the exec plane).

## Status as of 2026-11-05

| Slice | State | Evidence |
|---|---|---|
| FX surfacing | **API built, UI retargeted.** `konsol/orchestrator/fx.py` (PRD-18) exposes the whitelisted `get_fx_rates` over the governed `epm_staging.group_exchange_rates`, not the ERP feed. Its only in-repo caller is its test; the konsol-exec SPA it was written for is gone. Rates are shown to users in the `/close` app's **Rates & ownership** screen (`close-ui/src/nav.js`). | `fx.py:1-25`; `tests/test_orchestrator_fx.py`; `close-ui/src/nav.js` |
| Lineage and metrics | **Pure-python core only.** `lineage.py` (PRD-16) maps steps to the tables they produce and rolls up rows/duration per step. No view renders it. | `lineage.py:1-10` |
| Connection management | **Resolver only.** `resources.py` (PRD-17) resolves Airbyte/dbt/ClickHouse settings from run params and EPM Settings and lists them read-only; no management UI. The Connector doctype holds per-ERP credentials. | `resources.py:1-12`; `konsol/pipeline/doctype/connector` |
| Multi-ERP | **Design and switch exist; one extra adapter.** `erp_sources` var (default `[]`), `d365_fo` and `erpnext` adapters. | [Multi-ERP consolidation](https://docs.konsolidat.com/developer-guide/design/multi-erp-consolidation) |

Whether the GitHub issue is open was not checked from this machine.
