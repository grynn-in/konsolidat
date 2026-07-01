# Decision: Orchestrator P2 (konsol #58)

**Issue:** grynn-in/konsol#58 · **Status:** partial — next orchestrator increment

## Context
P2 = editable Pipeline Definitions, schedules, resume-from-step. Partly there:
`Pipeline Definition` doctype exists and is resolved in planning (#73),
`Pipeline Schedule` doctype exists, and `RESUME_FROM` is in the exec machine.
Missing: a **definitions editor** (desk/SPA), **actually running scheduled**
definitions, and an end-to-end **resume UX**.

## Options (sequencing the three sub-parts)
### A. Scheduler execution first (recommended)
Wire `Pipeline Schedule` → a scheduled job that triggers `plan_run`/`start_run`.
- **+** Highest operational value (unattended closes/builds); definitions already resolve, so the plumbing is short.
- **−** Needs a scheduler hook + single-flight interplay (reuse the existing guard/reaper).

### B. Definitions editor first
A desk/SPA form to compose step lists into a Pipeline Definition.
- **+** Makes pipelines user-editable (no fixture edits).
- **−** Lower urgency — the default + a couple of definitions cover current needs.

### C. Resume UX first
Surface resume-from-step in the redesigned exec plane (the machine supports it).
- **+** Nice recovery ergonomics.
- **−** Least value of the three; retry already exists.

## Recommendation
Order **A → B → C**. Scheduler execution is the biggest unattended-ops win and
builds directly on the now-resolved definitions; do it first. Fold the #74
hardening (planning-wedge guard) in alongside A, since scheduling multiplies the
run rate.

## Consequences
- Reuse the #66/#69/#76 single-flight guard + reaper for scheduled triggers (don't reinvent concurrency control).
