# Decision: Orchestrator P3 (konsol #59)

**Issue:** grynn-in/konsol#59 · **Status:** groundwork only — lowest priority

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
