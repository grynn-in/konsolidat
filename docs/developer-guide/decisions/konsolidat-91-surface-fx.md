# Decision: Surface FX rates in the app (konsolidat #91)

**Issue:** grynn-in/konsolidat#91 · **Status:** decided and implemented, 13 Sep 2026, in a different form (see Outcome)

## Outcome (13 Sep 2026)

Neither B nor C was built as described below. The decision on konsolidat #93 / konsol #103 went further than C: the group's exchange rates are **governed in konsol and are the only rates translation reads**. The ERP feed is no longer a rate source at all, only an input to a pre-fill.

- **C, superseded:** konsol's **Group Exchange Rate** holds one approved Closing and one Average rate per period, from each currency into a group reporting currency. It is the single source, not a `'manual'` override UNION'd with ERP rates. ([konsol#174](https://github.com/grynn-in/konsol/pull/174))
- **B, done differently:** users see the rates in the Group Exchange Rate list in konsol, and the read-only `konsol.api.fx_rates` returns the published governed rates per currency pair and period. ([konsol#174](https://github.com/grynn-in/konsol/pull/174))
- **Translation:** reads only `epm_staging.group_exchange_rates`. ([konsolidat#176](https://github.com/grynn-in/konsolidat/pull/176))

See the [Exchange Rates Guide](../../user-guide/exchange-rates-guide.md). The options below are kept as the record of what was weighed.

## Context
Part A (ISO-4217 currency seed + rates present in silver) is done (#98/#108).
Users still can't *see* the FX rates that drive translation, nor enter a manual
override. Two remaining parts: **B** = read-only surfacing of the rates already in
ClickHouse; **C** = a manual `Exchange Rate` doctype whose values are UNION'd into
the rate resolution as a `'manual'` source.

## Options
### B. Read-only CH view surfaced via the app (recommended first)
Expose `silver_exchange_rates` (and the effective closing/average/default per
pair/period) through `api.py` / `konsol.clickhouse` as a read-only report/view.
- **+** Cheap; high value (auditability — you can see exactly what rate translated an entity, ties to the CTA story).
- **+** No new source-of-truth, no write path, no governance questions.
- **−** Read-only; can't fix a bad/missing rate from the app.

### C. Manual Exchange Rate doctype
A doctype whose rows sync to `epm_staging.manual_exchange_rates`, UNION'd into
rate resolution as a `'manual'` erp_source (highest precedence).
- **+** Lets finance correct/supply rates without a data load.
- **−** New governed source-of-truth (precedence rules, publish lifecycle, audit); more surface area. Overlaps the Historical Equity Rate doctype pattern.

### C′. Both, sequenced
B now, C later.

## Recommendation
**B first, C later (C′).** The read-only view is a quick, safe auditability win
and is the thing users ask for most ("what rate was used?"). Do C only once
there's a concrete need to hand-enter rates, and model its precedence/lifecycle
on the existing Historical Equity Rate doctype.

## Consequences
- B pairs naturally with the exec-plane FX-surfacing item in konsol #59 (P3).
- C, if built, should generate/participate in the same rate-resolution the dbt models already use (single resolution path).
