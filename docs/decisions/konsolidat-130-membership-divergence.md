---
title: "Decision: Consolidation membership divergence (konsolidat #130)"
sidebar_label: "#130 Membership divergence"
description: Decision brief from the 2026-07-01 triage on the GROUP_EMEA / GROUP_CORP divergence between the Consolidation Group doctype and the dbt consolidation_groups data, with its status as of 2026-11-05.
---

# Decision: Consolidation membership divergence (konsolidat #130)

**Issue:** grynn-in/konsolidat#130 · **Status (2026-07-01):** needs owner sign-off (changes reported numbers)

:::note Provenance
Written for the 2026-07-01 open-issue triage (konsolidat `1ccafa9`, 2 July 2026). A recommendation marked "needs owner sign-off"; no sign-off by Deepak Pai is recorded in either repository, so the recommendation below must not be read as his decision. Text below is verbatim; it speaks of a dbt "seed" that no longer exists (see status). The section "Status as of 2026-11-05" was added when the page was ported.
:::

## Context
The **Consolidation Group doctype** places DEMF/GBMF under a `GROUP_EMEA`
sub-group, but the dbt **`consolidation_groups` seed** that
`gold_consolidated_trial_balance` actually joins on has all four entities flat
under `GROUP_CORP` — no `GROUP_EMEA` at all. Consequence: the 4 Historical Equity
Rate records keyed to `GROUP_EMEA` never match in gold, so DEMF/GBMF equity
silently translates at the **closing rate** instead of the IAS-21 historical
rate. This also blocks pair-level referential integrity (#92) and Phase 2 of
consolidation currency (#93).

This is a genuine correctness bug, but resolving it **changes DEMF's CTA/equity
translation in gold**, so it is a deliberate decision, not a mechanical fix.

## Options
### A. Align to the seed (recommended)
Treat `GROUP_CORP` (flat) as the operative truth: re-key the DEMF/GBMF HER records
+ fixture to `GROUP_CORP`, drop/retire the unused `GROUP_EMEA` sub-group in the
doctype, and **generate `consolidation_groups.csv` from the Consolidation Group
doctype** (like `dimension_mappings`/`cash_flow_categories`) so they can't drift again.
- **+** Makes the IAS-21 historical rates actually apply; removes a whole class of silent drift; one source of truth.
- **+** Matches the live, verified consolidation (NCI proven under GROUP_CORP; GROUP_EMEA appears nowhere in gold).
- **−** Changes gold: DEMF/GBMF equity now uses historical rate → CTA moves. Needs a numbers review + sign-off.

### B. Make `GROUP_EMEA` real
Add a genuine 2-tier hierarchy (GROUP_EMEA under GROUP_CORP) to the seed **and**
the gold consolidation, honoring the doctype.
- **+** Enables true EMEA sub-consolidation (ties to #93 Phase 2).
- **−** Much larger change (multi-level roll-up in gold); only worth it if EMEA sub-consolidation is actually a product requirement. Premature now.

### C. Leave as-is
- **−** DEMF/GBMF equity stays silently wrong; blocks #92 and #93 P2 indefinitely. Not acceptable long-term.

## Recommendation
**A** — align to the seed and generate the seed from the doctype. It fixes the
live bug, collapses the two sources into one, and unblocks #92 + #93. Gate on an
owner review of the resulting CTA delta (translate a before/after of DEMF).
Revisit **B** only if/when EMEA (or any) intermediate sub-consolidation becomes a
real requirement — then it lands as part of #93 Phase 2.

## Consequences
- Unblocks #92 pair-level referential integrity and #93 Phase 2.
- One follow-up: wire doctype→seed generation (new `regenerate_consolidation_groups_seed`), plus a data patch re-keying the 4 HER records.

## Status as of 2026-11-05

The two sources of truth the brief complains about have collapsed into one, by a different route than option A describes.

| Fact | Evidence |
|---|---|
| The dbt seeds directory was deleted on 12 Sep 2026; every reference table is konsol-owned. `consolidation_groups` is now `epm_gold.consolidation_groups`, written by the Consolidation Group doctype and read by dbt as a `source()`. The `regenerate_consolidation_groups_seed` function named in the brief was never written (no such symbol in either repository). | konsolidat `85dff3b` (#147), `9cd5126` (#144); `dbt_project/models/staging/_staging__sources.yml` |
| The data patch re-keying the Historical Equity Rate records from `GROUP_EMEA` to `GROUP_CORP` shipped: `konsol/patches/rekey_historical_equity_rate_to_group_corp.py` (idempotent, DB-level). | the patch file, docstring "(#130)" |
| Multi-level groups are now supported in the warehouse: consolidation "walks the tree, at the effective share" (`gold_entity_ownership`, `consolidation_ancestry`), so option B's "much larger change" has in effect been built for the general case. A konsol test covers "a sub-group is ownable too — GROUP_CORP's share of GROUP_EMEA". | konsolidat `934d264` (F2, #145); `konsol/tests/test_consolidation.py:237` |
| The pair-level referential-integrity check in Historical Equity Rate is still **not** enforced; its docstring still cites #130 as the reason. | `historical_equity_rate.py` `_validate_references` docstring |

Open for Deepak: the brief asked for an owner review of the CTA delta before re-keying. No record of that review was found. Whether the GitHub issue is open was not checked from this machine.
