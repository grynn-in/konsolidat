# Exchange Rates Guide

Konsolidat translates every foreign-currency ledger into the group's presentation currency using **Group Exchange Rates**. These are the group's own governed rates: group finance enters or accepts them in konsol, the Close Lead approves them, and consolidation reads nothing else. The ERP's rate tables are only a source for proposals.

This page is for group accountants and Close Leads who maintain those rates, and for administrators who look after the currency list.

## What a Group Exchange Rate is

A Group Exchange Rate is one rate for one key:

| Part of the key | Example | Meaning |
|-----------------|---------|---------|
| Group Reporting Currency | `USD` | The currency a consolidation group presents in |
| From Currency | `JPY` | An entity's functional (accounting) currency |
| Fiscal Year, Fiscal Period | `2026`, `3` | The period the rate applies to. Periods run 1–12, with 0 for opening balances (OPN) and 13 for the year-end close (CLS) |
| Rate Type | `Closing` or `Average` | Which statement lines it translates |

Each translated currency needs **both** an approved Closing rate and an approved Average rate for every period it is translated in:

| Rate Type | Translates | Notes |
|-----------|-----------|-------|
| **Closing** | Balance-sheet accounts (assets, liabilities) | The rate at the period end |
| **Average** | P&L accounts (revenue, expense) | The average rate for the period |
| Historical | Equity accounts that have a frozen rate | Not a Group Exchange Rate: it stays in the **Historical Equity Rate** doctype. See [Historical Equity Rates](consolidation-guide.md#historical-equity-rates-ias-21) |

An equity account with no historical rate translates at the Closing rate. An equity account with a historical rate still needs the period's Closing and Average rates to be approved: consolidation refuses a period that has no usable rates before it looks at equity.

An entity whose currency is the group's own currency translates at 1. You never enter a rate from a currency into itself.

### Where the group's presentation currency lives

The presentation currency is the **Reporting Currency** on the group's node in the **Consolidation Group** tree. It is a link to **ISO Currency**, and every group node must have one. Every entity below the node is translated directly into that currency (the direct method). There is no consolidation currency in EPM Settings; that field was removed (konsol #172).

A Group Exchange Rate can only be entered into a currency that is some group's Reporting Currency. If a sub-group presents in EUR and its parent in USD, each needs its own set of rates: EUR rates for the sub-group and USD rates for the parent.

## Entering a rate

Open **Group Exchange Rate** (Consolidation module) and click **New**.

| Field | Example | What to enter |
|-------|---------|---------------|
| Group Reporting Currency | `USD` | The group's presentation currency |
| From Currency | `JPY` | The currency being translated |
| Rate Type | `Closing` | Closing or Average |
| Fiscal Year | `2026` | |
| Fiscal Period | `3` | |
| Quote | `0.6607` | Units of the group currency per **Quoted Per** units of the from-currency |
| Quoted Per | `100` | 1, 10, 100, 1,000 or 10,000 |
| Reason for Change | | Only when asked (see [Checks on entry](#checks-on-entry)) |

When you save, konsol fills **Rate As Quoted** with the quote and its unit, for example `0.6607 USD per 100 JPY`. Read it back before you submit: it is the quickest check that the direction and the unit are right.

### Quote and Quoted Per

A quote always says how many units of the **group** currency you get for some units of the **from**-currency. The direction never flips. What changes is the unit, which works like the conversion factor in D365:

- A strong currency is quoted per 1: `1.27 USD per 1 GBP`.
- A weak currency is quoted per 100, 1,000 or 10,000 so it keeps its digits: `0.6607 USD per 100 JPY`, `0.6154 USD per 10,000 IDR`.

konsol stores quotes with 9 decimal places. A quote must keep at least 6 significant digits there, which means a quote below 0.0001 is refused with a suggestion to quote it per a larger unit.

### What gets published

konsol publishes the **true rate**: units of the group currency per **1** unit of the from-currency.

```
true rate = Quote ÷ Quoted Per
```

konsol does this division once, when it publishes. Consolidation uses the published rate exactly as it is: it never multiplies, divides or inverts a rate.

**Worked example: JPY.** The group presents in USD, and a Japanese entity (JPMF) reports in JPY. Treasury quotes the March closing rate as 0.6607 USD per 100 JPY.

| Field | Value |
|-------|-------|
| Quote | 0.6607 |
| Quoted Per | 100 |
| Rate As Quoted | `0.6607 USD per 100 JPY` |
| Published true rate | 0.6607 ÷ 100 = **0.006607** USD per JPY |

A JPY 50,000,000 receivable at the period end translates to 50,000,000 × 0.006607 = **USD 330,350**.

**Worked example: IDR.** An Indonesian entity (IDMF, an illustrative code) reports in IDR. The closing rate is 0.6154 USD per 10,000 IDR.

| Field | Value |
|-------|-------|
| Quote | 0.6154 |
| Quoted Per | 10000 |
| Rate As Quoted | `0.6154 USD per 10,000 IDR` |
| Published true rate | 0.6154 ÷ 10,000 = **0.00006154** USD per IDR |

IDR 2,000,000,000 of revenue translated at an average rate of 0.00006100 is **USD 122,000**. Entering the IDR rate per 1 (0.00006154) would be refused: at 9 decimal places it keeps only 5 significant digits, and konsol tells you to quote it per 10,000.

## Checks on entry

konsol refuses a rate that is almost certainly a typing or scaling error, and asks for a reason when a rate moves a long way.

### The magnitude check (refused)

Every **ISO Currency** has a **USD Reference (log10)**: roughly the base-10 logarithm of how many units of that currency buy 1 USD.

| Currency | USD Reference (log10) | Roughly |
|----------|----------------------|---------|
| USD | 0 | 1 per USD (the anchor) |
| EUR | −0.03 | 0.93 per USD |
| GBP | −0.10 | 0.79 per USD |
| JPY | 2.17 | 148 per USD |
| IDR | 4.21 | 16,200 per USD |

From two references, konsol works out roughly what a rate between them should be, and refuses a rate that is **more than 10 times** above or below it:

```
refused when | log10(true rate) − (reference of group currency − reference of from-currency) | > 1
```

For JPY into USD the expected rate is about 10^(0 − 2.17) ≈ 0.0068 USD per JPY. The real rate, 0.006607, is well within the band. If someone types `0.6607` with Quoted Per left at 1, the true rate is 0.6607, about 98 times the expected value, and konsol refuses it with a message that says so and suggests quoting per 10, 100, 1,000 or 10,000.

While a currency's USD Reference is current, the check catches a factor of 100 or more every time. A slip of exactly 10 times (Quoted Per 1,000 instead of 10,000) can pass it. That is what the move check below and the **Rate As Quoted** label are for.

Two more cases are refused:

- **No reference.** A currency with no USD Reference cannot take a rate at all. The message names the currency: set its USD Reference first (see [Maintaining USD references](#maintaining-usd-references)).
- **Not a positive number.** Zero and negative quotes are refused.

### The move check (needs a reason)

A rate that moves **more than 50%** from the previous approved rate for the same key, or from the ERP quote it was proposed from, is saved only with a **Reason for Change**. The comparison is on true rates, so re-quoting a rate per another unit is not a move. Moves that size do happen (the Argentine peso fell by more than half in December 2023), so the reason lets a real one through.

The previous approved rate is the latest approved rate for the same currencies and rate type in an earlier period; a period with no rate is skipped.

## Pre-filling from the ERP

If a connector brings in ERP exchange rates, konsol can propose drafts from them.

1. Open the **Group Exchange Rate** list.
2. Click **Pre-fill from ERP** (shown to Group Accountants, Close Leads and System Managers).
3. Enter the **Fiscal Year** and **Fiscal Period** and click **Propose**.

konsol works out which currencies the period needs (from the last consolidation build, or, before any trial balance for the period has arrived, from each entity's most recent period) and, for each missing key, creates a **draft**:

- A Closing proposal takes the ERP quote in force on the period's last day; an Average proposal takes the quote in force on its first day. Where the ERP has no rate of that type, its `Default` rate type is used.
- A rate the ERP does not quote directly can be taken from its inverse, or derived as a cross rate through a third currency. The **Source Note** says how each proposal was reached and lists every ERP source's quote. When sources disagree it starts with "ERP SOURCES DISAGREE".
- The proposal is quoted per the smallest unit that puts the quote at 0.1 or more, so JPY is proposed per 100.
- **Source** is set to `ERP pre-fill` and **ERP Quote** records what the ERP quoted. If you change the quote, Source becomes `Manual`.

Nothing is approved by the pre-fill. A key that already has a draft or an approved rate is left alone. A summary lists what was proposed, what already existed, which keys have no ERP quote, and which proposals were refused (by the magnitude check, or because they move more than 50% and need a person's reason). Enter those by hand.

The ERP quote is an input only. Consolidation never reads the ERP rate tables.

## Approving a rate

Submitting a Group Exchange Rate **is** the approval. There is no separate workflow.

| Who | Job title | Can |
|-----|-----------|-----|
| EPM Analyst | Group Accountant | Create, edit and delete drafts; pre-fill; amend a cancelled rate |
| EPM Admin | Close Lead | Everything above, plus **Submit** (approve) and **Cancel** |
| System Manager | System | Same as EPM Admin |
| EPM User, Entity Accountant | Viewer, Entity Accountant | Read only |

On approval:

- konsol refuses a second approved rate for the same key. Cancel the first one and amend it instead.
- konsol refuses the approval if the period is closed.
- After the save commits, konsol republishes every approved rate to the warehouse (`epm_staging.group_exchange_rates`). The next consolidation build uses it.

### What the home shows

In konsol-exec, a month's **Ownership & rates** stage summarises the period's rates, for example `2 rates missing · 3 rates to approve`:

- **N rates missing**: translated keys with no approved rate. While the period is open, a Group Accountant sees a "Group exchange rates · N missing" item with a **Pre-fill or enter** link.
- **M rates to approve**: drafts for the period. A Close Lead sees an "Approve M group exchange rates" item.
- If a group the period translates into has no Reporting Currency, or the warehouse cannot say which rates the period needs, the stage shows an error, because the period cannot close.

The list of needed rates comes from the last consolidation build, so ownership or currency changes made since then show after the next build.

### Closing a period

A period cannot be closed (**Period Status** moved to Closed or Locked) while any currency its ledgers translate lacks an approved Closing or Average rate, or a group it translates into has no Reporting Currency. The error names each missing key, for example `JPY → USD Average`.

Closing the period locks its rates: they can no longer be approved or cancelled.

## Correcting a rate

An approved rate cannot be edited. To replace it:

1. Make sure the period is open. If it is closed, reopen it in **Period Status** first (a Locked period only a System Manager can reopen); the reopen is recorded.
2. **Cancel** the approved rate (EPM Admin). A cancelled rate leaves the warehouse at once but stays in konsol as the audit trail; it cannot be deleted.
3. **Amend** it. konsol copies it to a new draft (`<name>-1`).
4. Enter the new quote and a **Reason for Change**. An amendment always needs one.
5. **Submit** the amendment to approve it, then rebuild and close the period again.

Drafts can be deleted freely.

## How consolidation uses the rates

`gold_consolidated_trial_balance` looks up each entity's rows by (entity currency, group reporting currency, fiscal year, fiscal period):

| Account | Rate used |
|---------|-----------|
| Entity currency = group currency | 1 |
| Equity with a Historical Equity Rate | The historical rate |
| Balance sheet | Closing |
| P&L | Average |

Only entities that are line-consolidated in the period need rates: those with a complete ownership chain and a method other than equity or none. An equity-accounted associate owes no rate.

**A build with an unusable rate is refused before anything is deleted.** The consolidated trial balance keeps its last figures, and the build fails with a message listing the first 50 keys, sorted, each with a reason:

| Reason | Meaning | Fix |
|--------|---------|-----|
| `missing` | The key has no approved Closing and Average rate | Pre-fill or enter the rates and approve them |
| `duplicate` | More than one approved rate of one type | Cancel the extra one (konsol normally refuses this) |
| `invalid` | A rate that is zero, negative or not a number | Cancel and amend it |
| `implausible` | More than 10 times from the USD references | Check Quoted Per; cancel and amend |

A message looks like this:

```
konsolidat#93 refused before anything was deleted: 2 translated key(s) without a usable
governed rate (konsol Group Exchange Rate): IDR->USD FY2026 P3 missing; JPY->USD FY2026 P3 missing. ...
```

A run is refused as a whole: one missing rate stops a full build. So a newly submitted trial balance in a new currency, or for a new period, blocks full builds until that period's Closing and Average rates are approved. The dbt test `assert_every_translated_currency_has_a_governed_rate` lists every key, not just the first 50.

The warehouse repeats the magnitude check, but it does not refuse a rate for a currency that has no USD Reference (konsol already refused it at entry); the magnitude tests warn about it instead.

To see the rates in use, open the Group Exchange Rate list in konsol, or call the read-only `konsol.api.fx_rates` API, which returns the published true rates.

## Adoption on upgrade

Sites that consolidated before Group Exchange Rate existed translated with the ERP's rates. When such a site is upgraded, `bench migrate` runs a one-time adoption: for every period the warehouse had already translated, it records the rate that period was translated at as an approved Group Exchange Rate, so the first build under governed rates gives the same figures.

- Adopted rates have **Source** `Adoption` and a **Source Note** that says where the rate came from and that it was set by the system, not reviewed by a person. Replace any of them (cancel and amend, while the period is open) if group finance sets another rate. The adoption is the only thing that can approve a rate in a closed period.
- A key that was translated at two different rates, or at the old 1.0 fallback because the ERP had no rate, is **not** adopted. The migrate log lists it as needing a person, and the build names it until a rate is approved.
- Before adopting, konsol fills in USD References for the shipped currencies where they are unset. If a currency it would adopt still has none, **the migrate stops**, adopts nothing, and prints what to do:

    ```
    Create or edit ISO Currency XYZ, set USD Reference (log10). Then rerun `bench migrate`
    ```

- The warehouse must be reachable: a migrate that cannot read it stops here rather than leave every period to fail at the next build.

Administrators can preview the adoption without writing anything:

```bash
bench --site <site> execute konsol.group_rates.adopt_erp_rates --kwargs "{'dry_run': 1}"
```

A fresh install has nothing to adopt. For what `deploy.sh` does around this, see [Deployment Guide → Governed exchange rates on upgrade](../admin-guide/deployment-guide.md#governed-exchange-rates-on-upgrade).

## Maintaining USD references

**USD Reference (log10)** is a field on **ISO Currency** (EPM Admin or System Manager can edit it). konsol ships a value for each of its 69 currencies, based on typical 2024–25 market levels, and fills it only where a site has none, so your edits survive every upgrade.

- It is a rough order of magnitude, not a rate. Refresh it only when a currency moves by a factor of three or more.
- 0 means "not set" for every currency except USD. A currency pegged 1:1 to the dollar (PAB, BSD, BMD) is therefore stored as 0.001, which is negligible for a 10× check.
- Values outside −5 to 10 are refused as typos.

To add a currency, create an **ISO Currency** with its code, name and minor unit, and set its USD Reference: the log10 of its units per 1 USD. A currency at 3,500 per USD has a reference of log10(3,500) ≈ 3.54.

## Limitations

- **One reference per currency for all periods.** A currency that has moved more than 10 times since the earliest period you translate (the Argentine peso, for example) can have its old rates refused by the shipped reference. Set the reference between the old and new levels. A currency that has moved more than 100 times cannot pass every period with one value. Effective-dated references are tracked in konsol #176 and not built yet.
- **Hyperinflation is not handled.** P&L accounts always translate at the Average rate. IAS 29 restatement, or translating a hyperinflationary economy's P&L at the Closing rate, is not supported.
- **Direct method only.** Every entity is translated straight into its group's Reporting Currency. Step-by-step consolidation through a sub-group's own currency is not built.
- **Rates are per fiscal period.** A daily or transaction-date rate cannot be entered.

## Next steps

- [Consolidation Guide](consolidation-guide.md): how translated amounts, CTA and ownership fit together
- [Intercompany Guide](intercompany-guide.md): matching and eliminating intercompany balances
- [FX Translation design](../developer-guide/design/fx-translation.md): the warehouse contract
