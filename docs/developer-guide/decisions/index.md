# Open-Issue Decisions

Decision briefs for every open issue as of the 2026-07-01 triage — the options
considered and the recommended path. Each links to its GitHub issue. Format:
Context → Options (with trade-offs) → **Recommendation** → Consequences.

| Issue | Topic | Recommendation (one line) |
|---|---|---|
| konsolidat #93 | [Consolidation currency](konsolidat-93-consolidation-currency.md) | Ship **Phase 1** (direct method) now; defer Phase 2 until #130 |
| konsolidat #130 | [Membership divergence](konsolidat-130-membership-divergence.md) | **Align to the seed** (GROUP_CORP) + generate seed from the doctype — needs owner sign-off |
| konsolidat #92 | [Historical Equity Rate — remaining](konsolidat-92-historical-equity-rate.md) | Add an **is-equity guard via a synced account cache**; pair-check after #130 |
| konsolidat #91 | [Surface FX rates](konsolidat-91-surface-fx.md) | **Part B first** (read-only CH view); Part C (manual doctype) later |
| konsolidat #131 | [Asset self-heal staleness](konsolidat-131-selfheal-staleness.md) | **Hash-guard + timeout** the heal |
| konsolidat #90 | [Productionize Airbyte](konsolidat-90-airbyte-prod.md) | Defer (P2); when needed, **Helm Airbyte on real k8s** |
| konsolidat #57 | [ClickHouse cluster mode](konsolidat-57-clickhouse-cluster.md) | Defer (scale-gated); prefer **managed CH or Keeper+shards** when scale lands |
| konsol #56 | [Orchestrator epic](konsol-56-orchestrator-epic.md) | Keep as tracker; roadmap P2 → P3 |
| konsol #58 | [Orchestrator P2](konsol-58-orchestrator-p2.md) | **Scheduler execution first**, then definitions editor, then resume UX |
| konsol #59 | [Orchestrator P3](konsol-59-orchestrator-p3.md) | Lowest priority; do **FX surfacing + basic lineage view** |
| konsol #74 | [Orchestrator hardening](konsol-74-orchestrator-hardening.md) | Fold into P2; **planning-wedge guard first** |
| konsol #55 | [Past-FY consolidation close](konsol-55-past-fy-close.md) | **Wire the FY selector through the close path**; do with P2 |

_These are recommendations, not commitments — the "needs sign-off" items (esp. #130) change reported numbers and want a deliberate call._
