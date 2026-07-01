# Decision: Consolidation currency (konsolidat #93)

**Issue:** grynn-in/konsolidat#93 · **Status:** next-round feature (biggest gap)

## Context
Today the group reporting currency is effectively hard-wired (USD in the seed).
There's no first-class way to (a) pick the group reporting currency, or (b) run a
multi-tier close where sub-groups consolidate in their own currency before
rolling up. The issue proposes two phases: **Phase 1** = direct method (one group
reporting currency, chosen in EPM Settings); **Phase 2** = step-by-step
sub-consolidation.

## Options
### A. Phase 1 only, now (recommended first step)
Add a `reporting_currency` to EPM Settings; thread it through
`gold_consolidated_trial_balance` translation (all subs → the one group currency,
direct method). CTA already exists.
- **+** Self-contained; unlocks non-USD groups; no hierarchy changes.
- **+** Highest value-per-effort; the FX machinery (rate types, CTA, historical equity) is already built.
- **−** No sub-consolidation (each entity translates straight to the group currency).

### B. Both phases now
Phase 1 **plus** step-by-step sub-consolidation (each sub-group consolidates in
its currency, then translates up).
- **+** Full capability.
- **−** Depends on a real intermediate-group hierarchy — which is exactly the unresolved #130 divergence. Building on that now bakes in the wrong structure; multi-tier roll-up + per-tier CTA is a large change.

### C. Do nothing
- **−** Group stuck in USD; blocks any non-USD parent. Not viable long-term.

## Recommendation
**A now, B later.** Ship Phase 1 (direct method via EPM Settings) as the next big
feature — it's bounded and immediately useful. **Defer Phase 2 until #130 is
resolved** (it needs a real, reconciled sub-group hierarchy); then Phase 2 builds
naturally on the doctype-driven seed.

## Consequences
- Phase 1 is independent and can start immediately.
- Phase 2 is explicitly gated on #130 (membership divergence) — sequence them.
