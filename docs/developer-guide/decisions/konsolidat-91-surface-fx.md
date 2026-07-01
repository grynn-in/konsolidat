# Decision: Surface FX rates in the app (konsolidat #91)

**Issue:** grynn-in/konsolidat#91 · **Status:** Part A done; B/C open

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
