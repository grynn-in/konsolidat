---
title: "Decision: Consolidation currency (konsolidat #93)"
sidebar_label: "#93 Consolidation currency"
description: The 13 Sep 2026 decision on where the group reporting currency lives and which exchange rates translation reads, with the options that were weighed.
---

# Decision: Consolidation currency (konsolidat #93)

**Issue:** grynn-in/konsolidat#93 · **Status:** decided 13 Sep 2026 (see Outcome)

:::note Provenance
The Outcome section was written in `repo/docs` when the decision was taken (13 Sep 2026) and records that "the user decided"; the Group Exchange Rate controller says the same ("Decided by the user on 13 Sep 2026"). Neither names the person, and the konsol `HANDOFF.md` names Deepak Pai as decider only from October 2026 onward, so this page does not attribute the 13 Sep decision to him. If it was his, he should say so and this note will be corrected. The options below are the 2026-07-01 triage brief (konsolidat `1ccafa9`), kept as the record of what was weighed. Text is verbatim. The section "Status as of 2026-11-05" was added when the page was ported.
:::

## Outcome (decided 13 Sep 2026)

The recommendation below (an EPM Settings field) was **not** taken. The user decided:

- **The presentation currency lives on each Consolidation Group node**, which is
  what the translation already read. `reporting_currency` is a Link to
  ISO Currency, validated: a group node (marked a group, or with no entity) must
  have one. The unused EPM Settings `consolidation_currency` field and its getter
  are removed. A reporting basis may override the currency later; that is not
  built. The direct translation method stays; Phase 2 stays deferred.
  ([konsol#172](https://github.com/grynn-in/konsol/pull/172))
- **Rates are governed, per fiscal period**: one approved Closing and one Average
  rate from each currency into a group reporting currency, in konsol's Group
  Exchange Rate. The ERP feed only pre-fills drafts; rates lock when their period
  closes. ([konsol#174](https://github.com/grynn-in/konsol/pull/174))
- **Translation reads only the governed rates**
  (`epm_staging.group_exchange_rates`); a missing rate fails the build.
  ([konsolidat#176](https://github.com/grynn-in/konsolidat/pull/176))

The options below are kept as the record of what was weighed.

## Context
Today the group reporting currency is effectively hard-wired (USD in the seed).
There's no first-class way to (a) pick the group reporting currency, or (b) run a
multi-tier close where sub-groups consolidate in their own currency before
rolling up. The issue proposes two phases: **Phase 1** = direct method (one group
reporting currency, chosen in EPM Settings); **Phase 2** = step-by-step
sub-consolidation.

## Options
### A. Phase 1 only, now (recommended first step)
Add a `reporting_currency` to EPM Settings; thread it through
`gold_consolidated_trial_balance` translation (all subs → the one group currency,
direct method). CTA already exists.
- **+** Self-contained; unlocks non-USD groups; no hierarchy changes.
- **+** Highest value-per-effort; the FX machinery (rate types, CTA, historical equity) is already built.
- **−** No sub-consolidation (each entity translates straight to the group currency).

### B. Both phases now
Phase 1 **plus** step-by-step sub-consolidation (each sub-group consolidates in
its currency, then translates up).
- **+** Full capability.
- **−** Depends on a real intermediate-group hierarchy — which is exactly the unresolved #130 divergence. Building on that now bakes in the wrong structure; multi-tier roll-up + per-tier CTA is a large change.

### C. Do nothing
- **−** Group stuck in USD; blocks any non-USD parent. Not viable long-term.

## Recommendation
**A now, B later.** Ship Phase 1 (direct method via EPM Settings) as the next big
feature — it's bounded and immediately useful. **Defer Phase 2 until #130 is
resolved** (it needs a real, reconciled sub-group hierarchy); then Phase 2 builds
naturally on the doctype-driven seed.

## Consequences
- Phase 1 is independent and can start immediately.
- Phase 2 is explicitly gated on #130 (membership divergence) — sequence them.

## Status as of 2026-11-05

The Outcome holds in the code.

| Decision point | Evidence |
|---|---|
| `reporting_currency` is a `Link` to ISO Currency on Consolidation Group; EPM Settings has no currency field (its tabs are ClickHouse, Airbyte, D365 Write-Back (Legacy), Airbyte Sync Status, dbt & Access Control, Close, Trial Balance Periods). | `consolidation_group.json`; `epm_settings.json`; konsol `11a846b0` (2026-09-13) |
| Group Exchange Rate: submittable, one Closing and one Average per (to-currency, from-currency, fiscal year, period); `prefill_from_erp` proposes, a person submits. | `group_exchange_rate.py` docstring; konsol `c80b1e97` |
| dbt reads `epm_staging.group_exchange_rates` only, through `rate_period_map()` in `macros/governed_rates.sql`; a `governed_rate_guard` pre-hook stops the build on a missing rate. `gold_consolidated_trial_balance`, `gold_business_combination_journal` and `gold_business_disposal_journal` read it. | konsolidat `cb180f2`; `grep -l group_exchange_rates dbt_project/models` |
| Later refinements, decided 6 Oct 2026: balance-sheet balances are retranslated at each period's closing rate; equity is never revalued; a year-end close carries no CTA. | konsolidat#257 (`d895c5c`), #259 (`7860177`); see [FX translation](https://docs.konsolidat.com/developer-guide/design/fx-translation) |
| Phase 2 (sub-consolidation in a sub-group's own currency) is not built; the warehouse walks multi-level groups at the effective share in one currency per group root. | `gold_entity_ownership.sql`; `gold_consolidated_trial_balance.sql` |
