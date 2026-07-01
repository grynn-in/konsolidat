# Decision: Consolidation membership divergence (konsolidat #130)

**Issue:** grynn-in/konsolidat#130 · **Status:** needs owner sign-off (changes reported numbers)

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
