---
title: "Decision: Orchestrator P2 (konsol #58)"
sidebar_label: "konsol #58 Orchestrator P2"
description: Decision brief from the 2026-07-01 triage on sequencing scheduler execution, a definitions editor and resume UX, with its status as of 2026-11-05.
---

# Decision: Orchestrator P2 (konsol #58)

**Issue:** grynn-in/konsol#58 · **Status (2026-07-01):** partial — next orchestrator increment

:::note Provenance
Written for the 2026-07-01 open-issue triage (konsolidat `1ccafa9`, 2 July 2026). A recommendation; it names no decider. Text below is verbatim. The section "Status as of 2026-11-05" was added when the page was ported.
:::

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

## Status as of 2026-11-05

| Part | State | Evidence |
|---|---|---|
| A. Scheduler execution | **Built.** `konsol.orchestrator.cron.run_due_schedules` runs every minute from `hooks.py` `scheduler_events["cron"]["* * * * *"]`; it enqueues every enabled Pipeline Schedule whose cron is due and stamps `last_run`. | `konsol/orchestrator/cron.py:104-136`; `konsol/hooks.py:120-124` |
| B. Definitions editor | **Desk form only.** The **Pipeline** doctype (renamed from Pipeline Definition in konsol `547ff9f8`) has a `Steps` child table of **Pipeline Step** rows (`step_id`, `step_type`, `depends_on`, `params`). No dedicated editor beyond the Frappe form was found. | `konsol/pipeline/doctype/pipeline/pipeline.json`, `pipeline_step.json` |
| C. Resume UX | **Core built, UI gone.** `konsol/orchestrator/resume.py` ("Resume-from-step + retry planning core, PRD-15") exists; the konsol-exec SPA that showed the step rail was removed with konsol#305. The `HANDOFF.md` inventory names the live step rail with per-step Retry/Resume as one of three things konsol-exec did that the Desk does not. | `resume.py:1`; konsol `HANDOFF.md` ("konsol-exec. A full task inventory…") |

The single-flight guard and reaper are reused by the scheduled path: `konsol/orchestrator/reaper.py` sweeps stuck Pipeline Runs every 15 minutes (`hooks.py:132`). Whether the GitHub issue is open was not checked from this machine.
