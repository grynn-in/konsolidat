---
title: "Decision: Historical Equity Rate — remaining (konsolidat #92)"
sidebar_label: "#92 Historical Equity Rate"
description: Decision brief from the 2026-07-01 triage on the last Historical Equity Rate findings (is-equity guard, pair check), with its status as of 2026-11-05.
---

# Decision: Historical Equity Rate — remaining (konsolidat #92)

**Issue:** grynn-in/konsolidat#92 · **Status (2026-07-01):** 5.5/6 fixed; open for finding #4 + pair-check

:::note Provenance
Written for the 2026-07-01 open-issue triage (konsolidat `1ccafa9`, 2 July 2026). A recommendation; it names no decider. Text below is verbatim. The section "Status as of 2026-11-05" was added when the page was ported.
:::

## Context
Of the 6 original findings, #1 (docstatus sync filter), #2 (ASOF as-of join), #3
(referential integrity via `validate()` — konsol #81), #5 (permissions), #6
(collision-safe autoname) are fixed. #4 is half-done: `validate()` rejects
non-positive rates, but there's **no check that `main_account` is an equity
account** — yet dbt applies the rate only when `is_equity = 1`, so a rate on a
non-equity account is silently dropped. Separately, referential integrity is
currently **existence-only** (not the `(group, entity)` pair) because of the #130
divergence.

## Options (finding #4 — is-equity guard)
### A. Query ClickHouse in `validate()`
Look up `is_equity` for the account in silver at save time.
- **+** Authoritative (same source dbt uses).
- **−** Couples doc save to ClickHouse availability; a CH outage blocks saves. Out of step with the rest of the app (validate is Frappe-only elsewhere).

### B. Validate against a synced account cache (recommended)
Sync the equity-account set into a small Frappe cache (a `Main Account` doctype
or a cached list refreshed on pipeline runs) and validate against that.
- **+** Frappe-only save path (no CH coupling); reuses existing sync patterns.
- **−** Needs a lightweight account-registry sync (small new plumbing); cache can lag until refresh.

### C. Defer / warn instead of block
dbt-side warn test that flags HER rows on non-equity accounts.
- **+** Zero coupling; surfaces the problem.
- **−** Doesn't prevent the bad entry at source (weaker than #3's intent).

## Recommendation
**B** for the guard (validate against a synced equity-account set — keeps saves
Frappe-only and consistent with #3's approach), with **C as an interim** dbt warn
test if the account sync isn't ready. **Pair-level referential integrity waits on
#130** (a pair check today would reject seed-correct keys given the divergence).

## Consequences
- Pair-check is explicitly sequenced after #130.
- If B's account-registry sync feels heavy, ship C now and upgrade to B later.

## Status as of 2026-11-05

Finding #4 is closed from both sides, by a route close to B plus C. The pair check is still open.

| Item | State | Evidence |
|---|---|---|
| App-side guard (B) | The **Main Account** doctype now exists as the governed group chart (konsol#182, decided 13 Sep 2026) with an `fx_method` field (`closing / average / historical`). konsol#239 refuses a `historical` declaration on a non-equity account at publish, so a chart governed today cannot carry one. `main_account` on Historical Equity Rate is a Link to Main Account. | `konsol/epm/doctype/main_account/main_account.json`; `historical_equity_rate.py` `_validate_references` docstring; `assert_historical_is_equity_only.sql` header ("konsol#239 refuses any such declaration at publish") |
| Warehouse-side test (C) | `assert_historical_is_equity_only` names a historical rate on a non-equity account for a chart that predates the guard; `assert_declared_historical_has_a_rate`, `assert_equity_historical_rate_is_asof`, `assert_equity_rate_coverage`, `assert_equity_uses_historical_rate` cover the rest. | konsolidat `9df89eb` (2026-09-16); `dbt_project/tests/` |
| Pair-level `(group, entity)` check | **Still not enforced.** `_validate_references` checks the group and the entity exist independently; its docstring says the pair "is intentionally NOT enforced yet" and cites #130. | `historical_equity_rate.py:61-140` |

Whether the GitHub issue is open was not checked from this machine.
