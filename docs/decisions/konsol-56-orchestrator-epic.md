---
title: "Decision: Orchestrator epic (konsol #56)"
sidebar_label: "konsol #56 Orchestrator epic"
description: Decision brief from the 2026-07-01 triage on keeping konsol #56 as the orchestrator tracker, with its status as of 2026-11-05.
---

# Decision: Orchestrator epic (konsol #56)

**Issue:** grynn-in/konsol#56 · **Status (2026-07-01):** tracker — P1 done, P2/P3 open

:::note Provenance
Written for the 2026-07-01 open-issue triage (konsolidat `1ccafa9`, 2 July 2026). A recommendation; it names no decider. Text below is verbatim. The section "Status as of 2026-11-05" was added when the page was ported.
:::

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

## Status as of 2026-11-05

| Fact | Evidence |
|---|---|
| The orchestrator package is in place: `konsol/orchestrator/` holds `api.py, cron.py, dag.py, definition.py, executor.py, fx.py, handlers.py, lineage.py, plan.py, reaper.py, resources.py, resume.py, run.py, state.py`. | directory listing, konsol `3e220ba8` |
| The doctypes were renamed on 2 July 2026: Pipeline Definition → **Pipeline**, Step Definition → **Pipeline Step**, Pipeline Step → **Run Step**. Pipeline Run, Pipeline Schedule exist. | konsol `547ff9f8` (#85); `konsol/pipeline/doctype/` |
| The konsol-exec SPA that was the epic's user interface was removed with konsol#305 (26 Sep 2026); runs are started from the Pipeline Run form's **Run Pipeline** button in the Desk, and the close runs in the `/close` app. | konsol `HANDOFF.md`; `pipeline_run.js:17` |
| P2 scheduling and resume are built (see [konsol #58](konsol-58-orchestrator-p2.md)); P3 has lineage, resources and FX modules but no UI (see [konsol #59](konsol-59-orchestrator-p3.md)). | `orchestrator/cron.py`, `resume.py`, `lineage.py`, `resources.py`, `fx.py` |

Whether the GitHub issue is open was not checked from this machine. Design: [konsol-exec as a pipeline orchestrator](https://docs.konsolidat.com/developer-guide/design/konsol-exec-orchestrator).
