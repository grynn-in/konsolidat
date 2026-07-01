# Decision: Orchestrator epic (konsol #56)

**Issue:** grynn-in/konsol#56 · **Status:** tracker — P1 done, P2/P3 open

## Context
The epic to turn konsol-exec into a real pipeline orchestrator (steps, params,
retries, schedules). **P1 is delivered + hardened**: `Pipeline Run/Step/Definition`
doctypes, `orchestrator/{dag,plan,run,api,lineage}.py`, single-flight + reaper +
heartbeat (#57 closed; #60/#66/#69/#73/#76). The exec-plane UI was redesigned
(#78). P2 (#58) and P3 (#59) remain.

## Options
### A. Keep #56 as the living epic/tracker (recommended)
Use it to sequence P2 → P3 and link the hardening follow-ups (#74).
- **+** Clear roadmap home; sub-issues stay independently actionable.

### B. Close #56, track P2/P3 only
- **−** Loses the epic view; the phases benefit from a shared narrative.

## Recommendation
**A.** Keep as the tracker. Sequence: **P2 (#58)** next, then **P3 (#59)**, folding
hardening (#74) into P2. Nothing to build directly on #56 itself.

## Consequences
- Progress is measured by #58/#59/#74 closing; #56 closes when they do.
