# Decision: Orchestrator hardening edge cases (konsol #74)

**Issue:** grynn-in/konsol#74 · **Status:** non-blocking hardening

## Context
Three edge cases from the #73 review on a now-stable orchestrator: (1) an
empty-definition run silently reports Completed; (2) no wedge guard during the
**planning** phase (the single-flight/reaper guards cover running, not planning);
(3) the heartbeat is stamped at persist time, not a true intra-step heartbeat.

## Options
### A. Fix all three now
- **+** Fully closes the review.
- **−** (3) true intra-step heartbeat needs step callbacks to beat mid-execution — more invasive than it looks.

### B. Prioritize the planning-wedge guard (recommended), defer the rest
Guard the planning phase (a crash between "run created" and "running" currently
can't be reaped → could wedge future runs given the single-flight guard); plus the
cheap empty-definition → explicit "nothing to do" status.
- **+** Addresses the only case that can *block future runs* (highest risk); (1) is a trivial status fix.
- **−** Leaves the cosmetic intra-step heartbeat for later.

### C. Defer all
- **−** The planning-wedge is a latent availability risk once scheduling (P2) raises run volume.

## Recommendation
**B, folded into P2 (#58).** The planning-wedge guard matters most once schedules
drive more runs, so do it *with* scheduler execution. Fix the empty-definition
status at the same time (one-liner). Treat the true intra-step heartbeat as a
later nicety (the persist-time heartbeat + reaper already prevent stuck-forever
runs).

## Consequences
- Sequenced with #58 P2 (scheduler execution) — same code paths, review once.
