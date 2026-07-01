# Entity Close & Reconciliation

## Problem
konsol consolidates entity trial balances into a group result, but it has no model
of the **legal-entity close** that must happen *before* consolidation — the
controls that make each entity's numbers trustworthy. Today the whole thing runs
as **one group build**: every entity's TB is computed and immediately
consolidated in the same dbt pass, with no per-entity lock, no sub-ledger
reconciliations, and no sign-off gate. A wrong or unreconciled entity silently
flows into the group.

This document specifies the entity-close control layer and how it feeds
consolidation, native to konsol (dbt gold models + doctypes + the konsol-exec
plane).

## Framing: konsol sits on top of D365
D365 is the ERP where the **transactional** close happens — posting sub-ledgers,
running depreciation, accruals, tax provision, payment processing. konsol is the
**control + consolidation** layer on top of the GL it ingests. Its close role is:

> **reconcile → verify → lock → consolidate → report**

So the close steps split into those that *run in D365* (konsol consumes the
resulting GL) and those that *konsol owns* (reconciliations, the lock, and
consolidation). This doc specifies the konsol-owned half.

## Two concepts that live in two places
These are routinely confused; the platform must keep them distinct.

**FX — revaluation vs. translation**

| | Revaluation | Translation |
|---|---|---|
| When | Entity close | Consolidation |
| What | Revalue an entity's *own* open foreign-currency monetary balances at the period-end rate → unrealized FX gain/loss on its books | Translate a foreign subsidiary's whole TB into group currency (BS=closing, P&L=avg, equity=historical) → CTA |
| Model | `gold_fx_revaluation` | `gold_consolidated_trial_balance` |

**Intercompany — reconciliation vs. elimination**

| | Reconciliation (operational) | Elimination |
|---|---|---|
| When | Entity close | Consolidation |
| What | Entity A's receivable from B must equal B's payable to A, at document level, *before* close — catches mismatches/disputes | Remove the agreed IC balances so the group doesn't double-count |
| Model | *(proposed — invoice-level)* | `gold_ic_eliminations` + `gold_ic_reconciliation` (GL-dimension level) |

## The entity-close control checklist
Each control is a **gate**: it must be green (matched / within tolerance) before an
entity's TB can lock. Status is against the current platform.

| # | Control | Runs in | konsol model / doctype | Status |
|---|---|---|---|---|
| 1 | Sub-ledger cut-off & posting (AP/AR/inv/FA/payroll) | D365 | consumes resulting GL | ✅ upstream |
| 2 | Depreciation / amortization | D365 | arrives as GL | ✅ upstream |
| 3 | Accruals / prepaids / deferrals / provisions | D365 or topside | `Consolidation Adjustment` doctype (manual) | ✅ |
| 4 | **FX revaluation** | D365 posts | `gold_fx_revaluation` (surface / validate) | ✅ |
| 5 | **Bank reconciliation** | — | *proposed* `gold_bank_recon` | 🔲 needs bank feed (MT940 / camt.053) |
| 6 | **Payment / cash-application rec** | — | *proposed* `gold_payment_recon` | 🔲 needs settlement/payment tables |
| 7 | **AP/AR sub-ledger → GL tie-out** | GL side present | *proposed* `gold_ap_subledger_recon` / `gold_ar_subledger_recon` | 🔲 first cut — needs `VendTrans`/`CustTrans` |
| 8 | Inventory / FA register → GL tie-out | — | *proposed* | 🔲 |
| 9 | **IC reconciliation (operational)** | — | *proposed* `gold_ic_operational_recon` | 🔲 needs IC-flagged sub-ledger |
| 10 | Tax provision | D365 | arrives as GL | ✅ upstream |
| 11 | Allocations | D365 or konsol | `gold_allocation_*` | ✅ |
| 12 | TB review & flux / variance | — | `gold_variance_*`, `gold_prior_year_comparison` | ✅ |
| 13 | **Entity TB lock + sign-off** | — | *proposed* Entity Close gate + `Pipeline Run` | 🔲 not built |
| → | Group consolidation | — | `gold_consolidated_trial_balance` → `gold_fully_consolidated_tb` | ✅ |

## Close sequence
```
per entity:  post sub-ledgers (D365) ─► depreciation / accruals / tax (D365)
             ─► FX revaluation ─► BANK rec ─► PAYMENT rec ─► AP/AR tie-out
             ─► IC rec (agree with counterparties) ─► flux review
             ─► ✔ LOCK entity TB   (all gates green)
                        │  repeat per entity, then fan-in
                        ▼
group:       translate ─► eliminate IC ─► NCI / CTA ─► topside
             ─► fully consolidated TB ─► statements
```

## Requirements

### R1: Reconciliation as a first-class result
Each reconciliation is a dbt gold model producing rows with a common shape so any
rec can be listed, drilled, and gated uniformly:

- `entity` (data_area_id), `fiscal_year`, `fiscal_period`
- `recon_type` (`bank` | `payment` | `ap_subledger` | `ar_subledger` | `ic` | …)
- `gl_side` amount, `subledger_side` amount, `variance` (= gl − subledger)
- `status` (`matched` | `unmatched` | `within_tolerance`), `tolerance`
- key + drill columns (vendor/customer/document/counterparty as applicable)

A control is **green** when no `unmatched` rows exist above tolerance for the
(entity, period).

### R2: New source data (Airbyte streams)
The sub-ledger detail is not ingested today (`epm_raw` is GL + dimensions + rates
+ budget only). Extend the `source-d365-fno` connector's stream list:

- AP/AR tie-out (first cut): `VendTrans`, `CustTrans` (+ masters `VendTable`,
  `CustTable` for statements/aging)
- Payment rec: settlement / payment-journal tables
- Bank rec: bank statement feed — **not** a D365 GL entity; a separate source
  (MT940 / camt.053 import or a bank-feed connector)
- IC operational rec: the IC-counterparty dimension already on GL, plus
  IC-flagged sub-ledger transactions for document-level matching

### R3: Entity Close gating
- An entity's TB can be **locked** for a period only when all applicable controls
  are green (or explicitly waived with a reason).
- Group consolidation for a period should refuse (or warn loudly) if a
  participating entity is unlocked or has open exceptions.
- Reuse `Pipeline Run` / `Pipeline Step` for the run record; the lock is a new
  per-(entity, period) state.

### R4: konsol-exec plane
- New **Entity Close** domain: scoped per entity (the plane already supports
  `scope`), its Layer Rail = the control checklist
  (`Reconcile → Review → Lock`), each stage green/red from R1.
- The controls surface in the **Assertions** domain too (a rec is an assertion
  that also carries its unmatched detail).
- Consolidation domain stays as-is; its precondition becomes "all entities
  locked".

### R5: Reporting / consumption
- Expose reconciliation results + exceptions as a K.EPM fact (`Fact Table` +
  `Measure`) so variances and aging are queryable from Excel, same pattern as
  the consolidated facts.

## Phased roadmap
1. **AP/AR control-account tie-out** — highest value, least new data (GL side
   exists; add `VendTrans`/`CustTrans`). Delivers R1 + one rec end-to-end.
2. **Entity Close gating + lock** (R3/R4) — the per-entity lock and the
   consolidation precondition; wire the Entity Close domain.
3. **Payment rec**, then **operational IC rec**.
4. **Bank rec** — last, because it needs a new external data source.

## Out of scope
- Running the transactional close itself (depreciation, accruals, tax, payment
  processing) — those stay in D365.
- Any external reconciliation engine — reconciliations are built native to
  konsol.
