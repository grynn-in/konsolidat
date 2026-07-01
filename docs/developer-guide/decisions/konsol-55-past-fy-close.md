# Decision: Past-FY consolidation close from the UI (konsol #55)

**Issue:** grynn-in/konsol#55 · **Status:** half-done

## Context
The konsol-exec Consolidation close defaulted to the current fiscal year with no
selector. Progress since: the backend `start_process(process_id, fiscal_year,
fiscal_period)` now passes them to `trigger_close_run`, and the exec-plane
redesign (#78) added a Fiscal Year + Period selector to the Execute launch form.
The remaining gap: the redesigned launch dispatches through the **orchestrator**
`start_run` path, so the selected FY/period isn't yet routed to the **close**
(`start_process` → `trigger_close_run`) path; and the raw `Close Run` doctype's
"Run Suite" button is still hidden on a new/Queued run.

## Options
### A. Route the selector through the close path (recommended)
In the Consolidation domain's launch, pass the chosen `fiscal_year`/`fiscal_period`
to `start_process` (frontend `startProcess` currently sends only `process_id`).
- **+** Small, targeted; backend already accepts the args; directly satisfies the acceptance ("start a close for any FY from the UI").
- **−** Needs a clear UX decision on Consolidation = orchestrator run vs close-assertion run (they're two triggers).

### B. Also fix the raw Close Run doctype action
Show a "Run Suite"/"Start" action on a new/Queued Close Run that calls
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
