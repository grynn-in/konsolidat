---
title: "Decision: Orchestrator hardening edge cases (konsol #74)"
sidebar_label: "konsol #74 Orchestrator hardening"
description: Decision brief from the 2026-07-01 triage on three orchestrator edge cases, with its status as of 2026-11-05.
---

# Decision: Orchestrator hardening edge cases (konsol #74)

**Issue:** grynn-in/konsol#74 · **Status (2026-07-01):** non-blocking hardening

:::note Provenance
Written for the 2026-07-01 open-issue triage (konsolidat `1ccafa9`, 2 July 2026). A recommendation; it names no decider. Text below is verbatim. The section "Status as of 2026-11-05" was added when the page was ported.
:::

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

## Status as of 2026-11-05

What the code shows; whether it was done as a response to #74 is not recorded in any commit message (no commit in konsol references `#74`).

| Edge case | State | Evidence |
|---|---|---|
| (2) Wedge guard | The reaper (`konsol/orchestrator/reaper.py`) releases Pipeline Runs stuck in an active state every 15 minutes, and `run.py` has a "#64 wedge guard" so an uncaught executor error does not leave a run in Running. `api.py:51` says the single-flight lock is held "so a crashed caller can never wedge it permanently". A guard specific to the planning phase was not identified by name. | `reaper.py:6`; `run.py:488-489`; `api.py:51`; `hooks.py:125-132` |
| (1) Empty definition | `run.py:117` treats an empty plan as progress 0; no explicit "nothing to do" status string was found. | `run.py:114-122` |
| (3) Intra-step heartbeat | Not identified in the code read; the reaper's staleness timeout (`STALE_RUN_TIMEOUT_MINUTES`) is "generous so a long dbt step is never falsely reaped". | `hooks.py:127-128` |

Open: confirm (1) and (2) against the issue thread before closing it.
