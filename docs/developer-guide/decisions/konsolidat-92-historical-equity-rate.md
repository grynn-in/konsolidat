# Decision: Historical Equity Rate — remaining (konsolidat #92)

**Issue:** grynn-in/konsolidat#92 · **Status:** 5.5/6 fixed; open for finding #4 + pair-check

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
