---
title: "Decision: Surface FX rates in the app (konsolidat #91)"
sidebar_label: "#91 Surface FX rates"
description: Decision brief from the 2026-07-01 triage on showing and entering FX rates in konsol, with its status as of 2026-11-05 (superseded by governed Group Exchange Rates).
---

# Decision: Surface FX rates in the app (konsolidat #91)

**Issue:** grynn-in/konsolidat#91 · **Status (2026-07-01):** Part A done; B/C open

:::note Provenance
Written for the 2026-07-01 open-issue triage (konsolidat `1ccafa9`, 2 July 2026). A recommendation; it names no decider. Text below is verbatim. The section "Status as of 2026-11-05" was added when the page was ported.
:::

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

## Status as of 2026-11-05

**Superseded by a stronger decision on 13 Sep 2026** (recorded on [konsolidat #93](konsolidat-93-consolidation-currency.md)): rates are governed, per fiscal period, in konsol's **Group Exchange Rate** doctype, and translation reads only those. That is neither B nor C as written:

| Part | What exists | Evidence |
|---|---|---|
| C (manual rates) | Replaced, not built. There is no `manual_exchange_rates` table or `'manual'` source. Instead every rate translation uses is a submitted Group Exchange Rate (one Closing and one Average per currency, period and group reporting currency); the ERP feed only pre-fills drafts (`konsol.group_rates.prefill_from_erp`) and a person accepts. Rates lock when their period closes. | `konsol/consolidation/doctype/group_exchange_rate/group_exchange_rate.py` docstring; konsol#174 (`c80b1e97`); konsolidat#176 (`cb180f2`); `macros/governed_rates.sql` |
| B (read-only view) | Built over the governed table, not over `silver_exchange_rates`: `konsol/orchestrator/fx.py` exposes the whitelisted `get_fx_rates` (PRD-18) and says the ERP feed "is not shown as the rates anywhere". Users see rates in the `/close` app's **Rates & ownership** screen. | `fx.py:1-25`; `close-ui/src/nav.js` |
| Single resolution path | Holds: dbt reads `epm_staging.group_exchange_rates` through `rate_period_map()` and fails the build on a missing rate (`governed_rate_guard`). `silver_exchange_rates` is an input to pre-fill only. | `gold_consolidated_trial_balance.sql`; `macros/governed_rates.sql` |

See [FX translation](https://docs.konsolidat.com/developer-guide/design/fx-translation). Whether the GitHub issue is closed was not checked from this machine.
