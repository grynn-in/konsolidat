# Month-End Close Guide

konsol-exec (`/konsol-exec`) is the workspace for the monthly close. Everyone in the close uses the same screen: the Close Lead, group accountants, entity accountants, budget reviewers and viewers. What each person sees in their work queue depends on their role and their entities.

Opening `/konsol-exec` takes you to the current calendar month. The period is part of the address: `/konsol-exec/2026/9` is period P09 of FY2026 (September 2026), so a link you paste into chat opens the same month for everyone. Period P of fiscal year Y is the month that starts on the 1st of month P of year Y.

You need an EPM or budget role to use it. Without one, konsol-exec says "Konsol needs an EPM or budget role. Ask your administrator for access."

## The Screen

```
┌──────────────────────────────────────────────────────────────────────────┐
│ Konsol │ FY2026 / P09 · Sep 2026 / Close            ⟳  Desk   AB Close Lead │  title bar
├───────────────────┬──────────────────────────────────────────────────────┤
│ FISCAL CALENDAR   │ Sep 2026                        Open  P09            │
│ ▾ FY2026 current  │ Month-end close · 12 entities in the close           │
│   Budget   Open   │ ┌─1──────┬─2──────┬─3──────┬─ … ─┬─8──────┐          │
│   OPN Opening…    │ │Source  │Trial   │Owner-  │     │Sign off│  stages  │
│   P01 Jan 2026    │ │data    │balances│ship &  │     │        │          │
│   …               │ └────────┴────────┴────────┴─────┴────────┘          │
│   P09 Sep 2026 3  │ NEEDS YOU 3                    │ Selected item       │
│   …               │ WAITING ON OTHERS 1            │                     │
│   CLS Year-end…   │                                │                     │
│ GROUP             │                                │                     │
├───────────────────┴──────────────────────────────────────────────────────┤
│ ● Worker healthy   Last build completed · 12 Sep 09:14   ● D365 …         │  status bar
└──────────────────────────────────────────────────────────────────────────┘
```

### Title Bar

- **Konsol** takes you back to the current month.
- **The path** says where you are, for example `FY2026 / P09 · Sep 2026 / Close`. There is no period dropdown: you choose a period in the navigator.
- **worker down** appears when the background worker is not responding. Runs, builds and uploads wait until it is back.
- **Refresh**, a link to **Desk**, and your name with your job title.

### Fiscal Navigator

The left panel, **Fiscal calendar**, lists fiscal years as folders: last year, this year (marked "current"), next year (marked "planning"), and any other year with a Period Status record (a period that has been closed, even if reopened since) or a budget cycle. The current year and the year you are looking at are open by default. An open year holds:

| Entry | What it is |
|---|---|
| **Budget** | The year's Budget Cycle, with its status. Opens the cycle in Desk. Shown only when a cycle exists |
| **OPN** | Opening balances (period 0) |
| **P01–P12** | The months, for example "P09 Sep 2026" |
| **CLS** | Year-end close (period 13) |

Each period shows its close state with its own symbol, not colour alone: **open**, **closed**, **locked** or **not started** (a month that has not begun). The selected period is highlighted and carries a red count of the items that need you.

Below the calendar, **Group** links to other places:

| Link | Shown to |
|---|---|
| Close checklist | Everyone |
| Entities | Everyone |
| Upload trial balances | Close Lead and System Manager ([Trial Balance Upload Guide](trial-balance-upload-guide.md)) |
| Trial balances | Close Lead, Group Accountant, Entity Accountant, System Manager |
| Adjustments, Reference data | Close Lead, Group Accountant |
| Connectors | System Manager |

### Month View

The month's heading shows its name, "Month-end close", how many entities are in the close, and who signed it off once it is closed. Beside it are the period's status (Open, Closed or Locked), its code, and, for the Close Lead and System Manager, an **Upload trial balances** button.

Below the heading, the **eight stages** of the month run left to right (see [The Eight Stages](#the-eight-stages)). Each shows its number, its name, its state and a one-line summary. Stages one of your roles owns are tinted and marked **You**. Clicking a stage opens its work: the Consolidate, Assertions and Sign off steps in konsol-exec, the other stages as a Desk list (filtered to the period for Trial balances, Intercompany and Adjustments).

Under the stages are two queues:

- **Needs you**: work your roles and entities own, with a count. Each row has a button to act.
- **Waiting on others**: work you depend on that someone else must do, with who that is (for example "Close Lead" or "Entity Accountants").

Both queues list the most urgent first: error, paused, incomplete, ready, running, idle, waiting, done. A person with two roles sees each item once. Selecting a row shows it in the **Selected item** panel on the right, with its stage, detail, entity and the same action.

### Status Bar

The bar at the bottom shows whether the background worker is healthy. For the Close Lead, Group Accountants and System Managers it also shows the last build and each enabled connector's last sync.

## The Eight Stages

Each stage feeds the next.

| # | Stage | Owned by | Its summary tells you |
|---|---|---|---|
| 1 | Source data | System | How many enabled connectors synced: "3 of 3 synced", "1 failed · 2 of 3 synced", "No connectors" |
| 2 | Trial balances | Entity Accountant | Manual trial balances in: "9 of 12 in · 2 draft", or "All 4 via connectors" |
| 3 | Ownership & rates | Group Accountant | Entities without ownership, group exchange rates missing or waiting for approval, drafts to submit; "Complete" when nothing is left |
| 4 | Intercompany | Group Accountant | IC Balance records: "1 draft · 3 submitted", "No balances" |
| 5 | Adjustments | Group Accountant drafts, Close Lead approves | "2 to approve", "1 draft", "4 approved", "None" |
| 6 | Consolidate | Close Lead | The latest consolidation build: "Latest build waiting for approval", "running", "done" or "failed" |
| 7 | Assertions | Close Lead | The period's close assertions: "Green · 26 of 26", "Red · 2 failed", "Signed off" |
| 8 | Sign off | Close Lead | "Ready to sign off", "Waiting on assertions", or Closed / Locked |

Two rules decide who is in a month:

- An entity is **in the close** when a submitted Ownership Period covers the first day of the month.
- An entity in the close **owes a manual trial balance** unless an enabled connector lists it among its legal entities.

Budgeting is an annual cycle, so it is not a monthly stage. Budget work appears in the queues of the people who own a layer, and the year's cycle is under **Budget** in the navigator.

A stage is in one of these states:

| State | Meaning |
|---|---|
| done | Finished for this month |
| running | Work in progress (a sync or a build) |
| paused | Waiting for an approval |
| error | Something failed and needs attention |
| incomplete | Work is left to do |
| ready | Everything before it is done; it can go ahead |
| waiting | Waiting for an earlier stage |
| idle | Nothing to do, or not started |

## Job Titles and Roles

The screen shows job titles. Permissions are granted through roles, whose names are unchanged.

| Role | Job title on screen | What it does |
|---|---|---|
| EPM Admin | **Close Lead** | Runs the close, approves builds and adjustments, signs off periods |
| EPM Analyst | **Group Accountant** | Drafts adjustments, rates, ownership, intercompany and allocations; requests builds |
| Entity Accountant | **Entity Accountant** | Uploads and submits trial balances and fills in the base budget, for their own entities only |
| Budget Submitter | Entity Accountant | The older name for the base budget layer, kept as an alias |
| Budget Controller, Budget Manager, Budget Approver | **Budget Reviewer** | The challenge, management and board budget layers; the Budget Manager locks the cycle |
| EPM User | **Viewer** | Reads periods, reports and close status for their entities |
| System Manager | **System** | Connectors and source data |

A person with several roles sees their first title in this order.

## Who Does What

| Work | Group Accountant | Close Lead | Entity Accountant |
|---|---|---|---|
| Trial balance for an entity | Reads | Uploads, submits, bulk upload | Uploads and submits, own entities |
| Ownership Period | Drafts | Approves (submits) | |
| Historical Equity Rate | Drafts and submits | Can also submit; cancels | |
| Group exchange rates | Pre-fills from the ERP or enters | Approves (submits) | |
| IC Balance | Drafts and submits | | |
| Consolidation Adjustment | Drafts, sends for approval, amends a reversed one | Approves, rejects, reverses | |
| Allocation Run | Drafts | Approves (submits) | |
| Build | Requests | Approves a pending build | |
| Sign off the period | | Closes and locks | |

A Consolidation Adjustment moves through these states:

| From | Action | To | Who |
|---|---|---|---|
| Draft | Send for Approval | Pending Approval | Group Accountant |
| Pending Approval | Approve | Approved | Close Lead |
| Pending Approval | Reject | Draft | Close Lead |
| Approved | Reverse | Reversed | Close Lead |

Approving is the submit: an approved adjustment does not change. To correct it, the Close Lead reverses it and a Group Accountant amends it into a new draft.

### What Appears in Your Queue

| Job title | Needs you | Waiting on others |
|---|---|---|
| Close Lead | Approve a pending build (with its risk and who asked), approve adjustments, ownership changes, allocation runs and group exchange rates, failed close assertions, **Sign off Sep 2026** | Missing trial balances (on Entity Accountants), missing group rates (on Group Accountants) |
| Group Accountant | Draft adjustments to send for approval, "Ownership missing for DE01", historical rates and IC balances to submit, missing group exchange rates to pre-fill or enter | Adjustments and group rates waiting for the Close Lead, missing trial balances |
| Entity Accountant | One row per assigned entity that owes a manual trial balance this month: submitted (View), draft (Submit) or not uploaded (**Upload trial balance**); base budget sheets for open budget cycles | |
| Budget Reviewer | Their layer's round for each open budget cycle | |
| System | Failed connectors; Entity Accountants who have no entity assigned (**Assign entities**) | |

An action you may not take is shown disabled, with the reason: "You don't have permission for this." The **Sign off** row stays disabled until the close assertions are settled ("Opens when close assertions are green.").

## Entity Access

Access to entities comes from **User Permissions** on Entity in Desk. Assigning a user to a group entity gives them every entity below it.

- A user with a restricted set of entities sees only those entities, in konsol-exec, in Desk lists and in Excel.
- An **Entity Accountant with no entity assigned sees no entity** at all. System Managers see a queue item listing such users.
- Other roles with no assignment see every entity, unless **Restrict Entities By Default** is on in EPM Settings.
- System Managers always see every entity.
- Stage counts are group-wide, but a user who is not a Close Lead, Group Accountant or System Manager only sees the entity codes behind them for their own entities. Connector and build detail in the status bar is shown to those three roles only.
- In Excel, a user with restricted access who reads an entity outside it, or leaves the entity blank in a plain `K.EPM` formula, gets `#VALUE!` "Not permitted to access entity …". See [Reporting Hierarchies](reporting-hierarchies-guide.md#the-entity-argument) for how `"ALL"` is limited.

## Closed Periods

### Closing, Locking and Reopening

The Close Lead (or a System Manager) signs a month off in the **Sign off** step:

| Status | Set by | Effect |
|---|---|---|
| **Open** | Default: a period nobody has closed is open | Work is accepted |
| **Closed** | **Close** (the button names the period) | New work against the period is refused. It can be reopened, or locked |
| **Locked** | **Lock**, from Closed | As Closed, and only a System Manager can reopen it ("PS-2026-9 is locked. Only a System Manager can reopen it.") |

You can close a period whose close assertions have not passed; the step warns that "the numbers have not been proven". A period cannot close while a currency it translates lacks an approved group exchange rate: see the [Exchange Rates Guide](exchange-rates-guide.md).

### What a Closed Period Refuses

The server refuses these actions in a period that is Closed or Locked, whichever screen they come from:

| Record | Refused | Message (for December 2099) |
|---|---|---|
| Consolidation Adjustment | Approve, reverse | "Cannot approve a consolidation adjustment: fiscal period 12 of FY2099 is closed." / "Cannot reverse a consolidation adjustment: …" |
| IC Balance | Submit, cancel | "Cannot submit an IC balance: fiscal period 12 of FY2099 is closed." / "Cannot cancel an IC balance: …" |
| Allocation Run | Submit, reverse | "Cannot submit an allocation run: fiscal period 12 of FY2099 is closed." / "Cannot reverse an allocation run: …" |
| Trial Balance Submission | Any save, submit, cancel | "Cannot submit a trial balance: fiscal period 12 of FY2099 is closed." / "Cannot cancel a trial balance submission: …" |
| Group Exchange Rate | Approve, cancel | "Cannot approve a group exchange rate: fiscal period 12 of FY2099 is closed." / "Cannot cancel a group exchange rate: …" |
| Ownership Period | Cancel, when any month it changes is closed | "Cannot cancel an ownership period: it changes fiscal period 12 of FY2099, which is closed." |
| Historical Equity Rate | Cancel, when any month it changes is closed | "Cannot cancel a historical equity rate: it changes fiscal period 12 of FY2099, which is closed." |
| Close runs in konsol-exec | Starting a run | "Cannot start this run: fiscal period 12 of FY2099 is closed." |
| Bulk trial balance upload | The entity-period | "FY2099 P12 is closed" |

A cancelled document leaves the warehouse, which is why cancelling is refused once the period is closed. To correct a closed period, reopen it, or post the correction in an open period.

### How the Home Shows It

konsol-exec disables only what the server would refuse, and says why on the row:

- An approval you can still open, but which the server will refuse, keeps its button and carries a note: "Can't approve: Dec 2099 is closed." A Group Accountant's draft adjustment says "Can't be approved: Dec 2099 is closed." You can still reject, edit or delete the draft in Desk.
- A trial balance draft takes no save in a closed period, so it can only be deleted. The note says who can: "Can't submit: Dec 2099 is closed. Ask an EPM Admin to delete the draft if it isn't needed." (Entity Accountants cannot delete.)
- **Upload trial balance** is not offered for a closed month. The Close Lead's **Upload trial balances** button on the month view still shows, but the upload check refuses every entity-period in a closed period.

## Builds

A build is the governed rebuild of the warehouse (a **Build Approval** in Desk). Builds are not tied to a period, so:

- Every open month shows the **latest** consolidation build in the Consolidate stage, labelled "Latest build …".
- A closed month shows "Not shown for a closed period" rather than borrow a later build.
- A build waiting in Pending Review appears in the Close Lead's queue as "Approve <scope> build" (for example "Approve consolidation build"), with its risk and who requested it.
- A **Running** build cannot be moved by hand. Only the build job, or the clean-up that fails a build stuck for 30 minutes, moves it on: "This build is running. Wait for it to finish, or for the reaper to fail it after 30 minutes, then reset it."

## Not Yet Available

- Intercompany differences in the Intercompany stage (it counts IC Balance records only).
- A close calendar with working-day deadlines, and nudging a named person rather than a role.
- Uploading a trial balance from the Selected item panel (use the row's button or the upload page).
- A status for each Budget Sheet in the navigator's budget folder.

## Next Steps

- [Trial Balance Upload Guide](trial-balance-upload-guide.md): single and bulk trial balances
- [Consolidation Guide](consolidation-guide.md): what the Consolidate stage builds
- [Exchange Rates Guide](exchange-rates-guide.md): group exchange rates for stage 3
- [Intercompany Guide](intercompany-guide.md): partners and eliminations
