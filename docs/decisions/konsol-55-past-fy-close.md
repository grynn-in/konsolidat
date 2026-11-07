---
title: "Decision: Past-FY consolidation close from the UI (konsol #55)"
sidebar_label: "konsol #55 Past-FY close"
description: Decision brief from the 2026-07-01 triage on starting a close for any fiscal year from the UI, with its status as of 2026-11-05.
---

# Decision: Past-FY consolidation close from the UI (konsol #55)

**Issue:** grynn-in/konsol#55 · **Status (2026-07-01):** half-done

:::note Provenance
Written for the 2026-07-01 open-issue triage (konsolidat `1ccafa9`, 2 July 2026). The brief below is a recommendation by the author of that commit; it names no decider. The one change to the text is the doctype name: the close doctype was renamed to **Assertion Run** on 2 July 2026 (konsol `e61594dc`, #86). The section "Status as of 2026-11-05" was added when the page was ported to this site.
:::

## Context
The konsol-exec Consolidation close defaulted to the current fiscal year with no
selector. Progress since: the backend `start_process(process_id, fiscal_year,
fiscal_period)` now passes them to `trigger_close_run`, and the exec-plane
redesign (#78) added a Fiscal Year + Period selector to the Execute launch form.
The remaining gap: the redesigned launch dispatches through the **orchestrator**
`start_run` path, so the selected FY/period isn't yet routed to the **close**
(`start_process` → `trigger_close_run`) path; and the raw Assertion Run doctype's
"Run Suite" button is still hidden on a new/Queued run.

## Options
### A. Route the selector through the close path (recommended)
In the Consolidation domain's launch, pass the chosen `fiscal_year`/`fiscal_period`
to `start_process` (frontend `startProcess` currently sends only `process_id`).
- **+** Small, targeted; backend already accepts the args; directly satisfies the acceptance ("start a close for any FY from the UI").
- **−** Needs a clear UX decision on Consolidation = orchestrator run vs close-assertion run (they're two triggers).

### B. Also fix the raw Assertion Run doctype action
Show a "Run Suite"/"Start" action on a new/Queued Assertion Run that calls
`trigger_close_run` with the form's FY/period.
- **+** A doctype-level fallback path; unblocks the stuck-Queued case.
- **−** Secondary to A; more surface.

### C. Both (A then B).

## Recommendation
**A, done alongside P2 (#58).** It's the smallest change that meets the acceptance,
and it touches the same run-trigger wiring the P2 scheduler work will, so review
them together. Add **B** if the raw-doctype path is still needed after A.

## Consequences
- Resolve the "Consolidation domain → which trigger" question as part of A (orchestrator run vs close-assertion suite) — document it so the exec plane is consistent.

## Status as of 2026-11-05

The problem this brief describes no longer exists in the form described, because the surface it describes was replaced.

| Fact | Evidence |
|---|---|
| konsol-exec, `control_api.py` and `start_process` were removed. The close runs in the `/close` app (konsol#305 Delivery 1, merged 26 Sep 2026). | konsol `HANDOFF.md` ("Removed: konsol-exec, `home_api`, `home_model`, `control_api`"); `konsol/control_api.py` deleted in `0387e48f` (2026-09-27) |
| The close path takes the year and period from the caller. `run_checks(fiscal_year, fiscal_period)` in `konsol/close/checks_api.py` and `trigger_close_run(fiscal_year=None, fiscal_period=None)` in `konsol/consolidation/doctype/assertion_run/assertion_run.py` (POST-only; Close Lead, Group Accountant or System Manager may start a run). | the two functions; the Period Close Desk report (konsol `8d4877dc`, 2026-11-05) runs checks and signs off from a period row |
| Option A versus B was never decided as written; the replacement made both moot. | no commit references konsol#55 in either repository (`git log --grep '#55'` is empty in konsol) |

Whether issue #55 is closed on GitHub was not checked from this machine. See [Period Close guide](https://docs.konsolidat.com/user-guide/period-close-guide) and the [period close API](https://docs.konsolidat.com/api-reference/api-close).
