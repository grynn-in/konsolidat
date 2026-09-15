# Business Combinations: acquisition, amortisation and disposal journals

konsolidat#198 (with #179 pre-acquisition history and #180 derecognition on disposal).

## Problem

Until #198 the warehouse posted the acquisition accounting as one-sided rows:
`gold_acquisition_adjustments` debited goodwill and fair-value adjustments to the
hardcoded accounts `'1800'` / `'1900'` with no credit, and `gold_disposal_adjustments`
posted a gain or loss and a CTA recycling amount on a pseudo-account `'DISPOSAL'`
with no counterpart and without taking the disposed entity's balances out of the
group. The consolidated balance sheet could not balance in any acquisition or
disposal period, and `assert_end_to_end_bs_balances` (PRD-22) rightly failed on
every one of them. The inputs were also loose: the purchase price sat on the
Ownership Period, and nothing declared which accounts to post to.

The rule now: **every consolidation journal is double entry, posted once in its
period as movements, in group currency, from a submitted deal document, to accounts
the group declared.** dbt never assumes an account code or a policy; where an input
is missing the build names it and stops.

## The three layers

```
konsol (Frappe)                        ClickHouse                      dbt (gold)
──────────────────────────────         ───────────────────────────     ─────────────────────────────────────
Consolidation Group root row  ──sync──▶ epm_gold.consolidation_groups  ─┐
  declared accounts + policy             (17 account/policy columns)    │
Business Combination (submit) ──sync──▶ epm_staging.business_combinations        gold_business_combination_journal  ACQ-…
  Consideration lines                    business_combination_consideration     │
  Acquired Balance Sheet lines           business_combination_acquired_balances  ├─▶ gold_goodwill_amortisation_journal GWA-…
  Acquisition Costs lines                business_combination_costs              │
Business Disposal (submit)    ──sync──▶ epm_staging.business_disposals           └─▶ gold_business_disposal_journal   DSP-…
  Proceeds lines                         business_disposal_proceeds                          │
                                                                                            ▼
                                                                          layer 6 of gold_fully_consolidated_tb
                                                                          → gold_consolidated_ytd, gold_consolidation_journal,
                                                                            gold_consolidation_waterfall, PRD-22
```

1. **konsol owns the inputs.** The deal is a submittable document (submit = approval;
   cancel only while its period is open). The root row of the Consolidation Group
   (`data_area_id = ''`) carries the declared accounts and the Consolidation Policy.
   Only submitted rows reach the warehouse, so every row dbt reads is an approved deal.
2. **The warehouse tables are konsol's, DDL in both repos.** `clickhouse/init-db.sql`
   creates the six deal tables and the 17 new `consolidation_groups` columns;
   `tests/test_deal_tables_ddl.py` pins the bodies verbatim, and
   `dbt_project/models/staging/_staging__sources.yml` declares them as sources. The
   column-level contract is in the [staging tables](../../data-dictionary/staging-tables.md)
   page.
3. **dbt posts the journals.** Three models, one journal id per deal, every journal
   balanced by construction and proved balanced by a singular test. Layer 6 of
   `gold_fully_consolidated_tb` unions them (with the P&L proration that stays in
   `gold_acquisition_adjustments`), so they flow into YTD, the consolidation journal,
   the waterfall's acquisition/disposal column and the PRD-22 balance check.

Shared mechanics, the same in all three journals:

- **Dates → periods** through `epm_staging.fiscal_periods` by
  `start_date <= date <= end_date`, never by month. A Closing period (one day inside
  the last Regular period) is skipped, so a deal lands in the Regular period; 12-, 13-
  and non-calendar years work.
- **Currency**: consideration, cost and proceeds lines translate from their own
  currency, acquired and opening balances from the entity's accounting currency, to
  the group's `reporting_currency` at the period's governed **Closing** rate
  (`rate_period_map()` + `epm_staging.group_exchange_rates`). A line already in
  group currency translates at 1.
- **Sign**: debit positive, credit negative, in `adjustment_amount`.
- **Columns** as the other consolidation layers (`consolidation_group, data_area_id,
  fiscal_year, fiscal_period, main_account, account_name, adjustment_type,
  adjustment_amount`) plus `journal_id`, `line_no`, `account_role` and `deal`.

## Worked example (the fixtures' deal)

Group `ZZG` reports in USD; entity `ZZS` keeps its books in EUR; EUR→USD closing
rate 1.0 in every period used, so the figures read the same in both currencies.
The root row declares: goodwill `ZZ1800`, FVA `ZZ1900`, investment `ZZ3500`, NCI
`ZZ3400`, bargain-purchase gain `ZZ4900`, disposal gain/loss `ZZ4950`, deal
settlement `ZZ1000`, amortisation expense `ZZ6900`, acquisition costs `ZZ6950`. The
chart flags `ZZ3000` share capital and `ZZ3100` retained earnings as equity.

`ZZG` acquires `ZZS` on 2026-03-15 (FY2026 P3) for 8,300 USD cash. The acquired
balance sheet konsol recorded (entity currency, Dr +, Cr −):

| Account | Book | FVA |
|---|---|---|
| ZZ1100 receivables | +200 | |
| ZZ1420 property | +600 | +930 |
| ZZ2100 payables | −150 | |
| ZZ3000 share capital | −100 | |
| ZZ3100 retained earnings | −550 | |

Net assets at book = 650 (the equity), fair-value net assets = 650 + 930 = 1,580.

### The acquisition journal `ACQ-ZZG-ZZS-2026-03-15` (100%)

| line_no | account_role | Account | USD | Rule |
|---|---|---|---|---|
| idx | `equity_eliminated` | ZZ3000 | +100 | −(book) of every acquired-balance row the chart flags `is_equity`, 100% whatever the share: pre-acquisition equity is never group reserves |
| idx | `equity_eliminated` | ZZ3100 | +550 | |
| 101 | `fva` | ZZ1900 | +930 | Dr `fair_value_adjustment_account` by Σ FVA (100%) |
| 102 | `goodwill` | ZZ1800 | +6,720 | consideration (+ capitalised costs) + NCI − (net assets + FVA) = 8,300 − 1,580 |
| 103 | `investment` | ZZ3500 | −8,300 | Cr `investment_account` by the consideration |
| | | **Σ** | **0** | |

Net assets at acquisition is −Σ(eliminated equity), the figure the equity lines
carry, so the journal closes whatever the asset and liability rows sum to.
`measurement_basis` records how the net assets were measured (design §3 precedence:
`acquired_balances` → `header_net_assets` → `measured_from_tb`; today only the first
posts, `assert_acquisition_measured_in_period` warns when the third would be late).

**Line 0, `opening_balance`** (only when the entity has trial-balance history before
the acquisition period): the entity's ownership window starts at the acquisition,
so `gold_consolidated_trial_balance` never carries its opening position. The journal
brings in every balance-sheet account at its balance at the last pre-acquisition
period-end (100%, from `gold_trial_balance`, year-end close rows included), plus a
residual line to the chart's `is_retained_earnings` account when those balances do
not sum to zero (a mid-year position whose result still sits in P&L). Line 0 sums to
zero on its own. The `business_combination_history.sql` fixture (closing rate 1.25)
shows it: five opening lines 250 / 750 / −187.5 / −125 / −687.5, then the equity
eliminated 125 / 687.5, FVA 1,162.5, goodwill 6,325, investment −8,300.

**Line 104, `nci`** (share below 100%; `business_combination_80pct.sql`, 80% for 8,300):

| `nci_measurement` | NCI (Cr ZZ3400) | Goodwill | Rule |
|---|---|---|---|
| `partial` | −316 | 7,036 | NCI = (net assets + FVA) × (1 − share) = 1,580 × 0.2; goodwill = 8,300 + 316 − 1,580 |
| `full` | −2,075 | 8,795 | NCI = consideration ÷ share × (1 − share) = 8,300 ÷ 0.8 × 0.2 (IFRS 3.32, NCI at the fair value the price implies); goodwill = 8,300 + 2,075 − 1,580 |

The equity elimination and the FVA stay 100% in both cases.

**Partial share (open: konsolidat#204).** The NCI arithmetic above is right on its own,
but layer 1 of `gold_fully_consolidated_tb` carries a full-method subsidiary at the
parent's *share* (an 80% entity contributes 80% of every account), while the IFRS 3
template brings in 100% of the acquired net assets and books the minority as an NCI
line — so on an 80% deal the group balance sheet would count the minority twice. Until
#204 decides how layer 1 and the journals share the minority, a submitted combination
with `share_acquired_pct < 100`, and a submitted disposal with `share_disposed_pct <
100` or `retained_interest_pct > 0`, is **refused by name**: `assert_acquisition_
accounts_declared` / `assert_disposal_accounts_declared` emit one row per such deal
(`field = 'share_acquired_pct'` / `'share_disposed_pct'`, reason "partial-share deals
wait for konsolidat#204: layer 1 carries the entity at its share") and stop the build,
whatever the root row declares. `business_combination_80pct.sql` keeps proving the
NCI arithmetic through the balance tests, selected with `--exclude
assert_acquisition_accounts_declared` (its header says so).

**Line 105, `bargain_gain`** (`business_combination_bargain.sql`, 100% for 1,200):
the goodwill figure is 1,200 − 1,580 = −380. Under `bargain_purchase = 'Recognise
gain'` the journal posts Cr ZZ4900 −380 and no goodwill line (IFRS 3.34: a gain,
never negative goodwill). Under `'Refuse'` the deal posts **nothing** and
`assert_bargain_purchase_refused` (error) names it — deal, group, amount — so the
build stops until the Business Combination is reassessed (IFRS 3.36).

**Lines 110+idx `costs` / 130+idx `proceeds`** (`business_combination_costs.sql`:
Legal 120 USD, Advisory 80 EUR): the settlement side is the group's
`disposal_proceeds_account` — the account the group settles deal cash through, in
both directions.

| `acquisition_costs_treatment` | Lines | Goodwill |
|---|---|---|
| `Expense` | Dr ZZ6950 120 / Cr ZZ1000 −120; Dr ZZ6950 80 / Cr ZZ1000 −80 | 6,720 (IFRS 3.53: costs of the period, outside goodwill) |
| `Capitalise` | Cr ZZ1000 −120; Cr ZZ1000 −80 | 6,920 (the costs join the consideration) |

Capitalised costs do not enter the `full` NCI measurement: the price paid is the
fair-value signal, the deal's costs are not.

### The amortisation journal `GWA-ZZG-ZZS-2026-03-15`

Only when the root row declares `goodwill_treatment = 'Amortise'` with
`goodwill_amortisation_years > 0`; empty under `'Impairment only'`. Straight line over
years × the Regular periods the calendar declares for the acquisition year (12 on a
monthly calendar, 13 on a 4-4-5 one), from the acquisition period until fully
amortised, the disposal period (exclusive), or the end of the declared calendar.

| line_no | account_role | Account | USD per Regular period |
|---|---|---|---|
| 1 | `amortisation_expense` | ZZ6900 | +56 |
| 2 | `goodwill` | ZZ1800 | −56 |

`goodwill_amortisation.sql`: 10 years → 120 instalments of 6,720 ÷ 120 = 56 from
FY2026 P3 to FY2036 P2, 240 rows; each instalment is the rounded cumulative share
minus the previous one, so they sum to the goodwill exactly whatever the division
leaves. `goodwill_amortisation.disposal.sql`: the same deal disposed 2027-03-31 →
12 instalments (FY2026 P3 .. FY2027 P2, Σ 672), and the disposal journal
derecognises 6,720 − 672 = 6,048.

### The disposal journal `DSP-ZZG-ZZS-2027-03-15`

`business_disposal.sql`: `ZZS` sold 100% on 2027-03-15 (FY2027 P3) for 9,000 USD,
Impairment only. Its trial balance at FY2027 P3: ZZ1000 100, ZZ1100 200, ZZ1420 600,
ZZ2100 −150, ZZ3000 −100, ZZ3100 −650 (net assets 750).

| line_no | account_role | Account | USD | Rule |
|---|---|---|---|---|
| 0 | `derecognised` | ZZ1000 | −100 | every **non-equity** balance-sheet account at −(cumulative balance at the disposal period-end) × 100%, at the period's Closing rate |
| 0 | `derecognised` | ZZ1100 | −200 | |
| 0 | `derecognised` | ZZ1420 | −600 | |
| 0 | `derecognised` | ZZ2100 | +150 | |
| 101 | `goodwill` | ZZ1800 | −6,720 | −(goodwill the ACQ journal(s) booked for the entity in this group) net of GWA lines before the disposal period |
| 102 | `fva` | ZZ1900 | −930 | −(FVA booked at acquisition); there is no FVA run-off model, so the whole amount remains |
| 103 | `cta` | `CTA` | (0 here) | −Σ `gold_fx_revaluation.cta_amount` of the entity in the group up to the disposal period (IAS 21.48 recycling); the group's CTA line |
| 104 | `nci` | ZZ3400 | (none here) | −Σ ACQ `nci` lines (derecognised) |
| 110+idx | `proceeds` | ZZ1000 | +9,000 | Dr `disposal_proceeds_account` per proceeds line (the header's `total_proceeds` at 110 when there are no lines) |
| 199 | `gain_loss` | ZZ4950 | −600 | balancing line: 9,000 − (750 + 6,720 + 930) = 600 gain, a credit |
| | | **Σ** | **0** | |

The equity accounts are not touched: the acquisition eliminated the pre-acquisition
part, and the profits retained since belong to the group (IFRS 10.B98). The current
year's result to the disposal stays in group P&L; it is inside the net assets
derecognised, so it is inside the gain or loss.

Only the **full** disposal is in scope (`retained_interest_pct = 0`). A disposal that
keeps an interest posts nothing and `assert_disposal_gain_loss_exists` names it (the
remeasurement of the retained interest is out of scope, design §5/§7); it still stops
the amortisation schedule.

## The policy table (Consolidation Policy on the group root)

Every setting is required once the group has a Business Combination; there are no
defaults. `assert_acquisition_accounts_declared` (error) stops the build when a
policy is missing or not one of its options, or when an account the deal needs is
not declared or not a posting account of the chart. The journals read an undeclared
value as the fallback in the last column only so that the model compiles; the guard
is what makes that fallback unreachable in a passing build.

| Field | Options | Effect in the journals | Fallback the guard stops |
|---|---|---|---|
| `accounting_framework` | IFRS / US GAAP / Local (+ `framework_note`) | labels; konsol's `validate()` restricts the combinations (US GAAP → Full NCI; IFRS → Impairment only; Local needs a note). dbt does **not** re-check these | — |
| `nci_measurement` | `partial` / `full` | NCI = share of fair-value net assets / NCI at the fair value the price implies, goodwill then includes the NCI's share | `partial` |
| `goodwill_treatment` | Impairment only / Amortise (+ `goodwill_amortisation_years`) | GWA journal empty / monthly Dr `goodwill_amortisation_expense_account`, Cr `goodwill_account` | Impairment only |
| `acquisition_costs_treatment` | Expense / Capitalise | Dr `acquisition_costs_account` per cost line, Cr settlement / costs join consideration, only the settlement credit posts | Expense |
| `bargain_purchase` | Recognise gain / Refuse | Cr `bargain_purchase_gain_account` / the deal posts nothing and `assert_bargain_purchase_refused` stops the build | Recognise gain |
| `measurement_period` | Off / 12 months | a konsol rule (whether a submitted deal may be amended within 12 months and re-posted retrospectively); the journals recompute from the submitted rows on every build either way | — |

Declared accounts and when each is required: `goodwill_account` and
`investment_account` (consideration > 0); `fair_value_adjustment_account` (any FVA);
`nci_account` (share < 100); `bargain_purchase_gain_account` (a bargain under
Recognise gain); `disposal_gain_loss_account` and `disposal_proceeds_account`
(disposal, or acquisition costs); `goodwill_amortisation_expense_account` (Amortise);
`acquisition_costs_account` (costs under Expense). The chart must flag
`is_retained_earnings` when the entity has pre-acquisition history (line 0's
residual) and `is_equity` on the equity leaves (the elimination).

## What is not configurable, and why

- **The journal templates** above and the double-entry rule. They are the accounting
  mechanics of IFRS 3 / IAS 21 / IFRS 10; a group chooses its policy, not whether its
  journals balance.
- **Measurement basis and rates**: the acquisition-date balance sheet konsol recorded
  (or the header figure) comes first; the Closing rate of the deal's period translates
  every line. A late period-end proxy is named, not chosen.
- **Which equity is eliminated**: everything the chart flags `is_equity` on the
  acquired balance sheet, 100%. The share only moves the NCI line.
- **Retained interest, step acquisitions, changes without loss of control, goodwill
  impairment testing**: out of scope and **named** by the tests rather than posted
  with a guess (design §7). The escape hatch below covers them until a template exists.
- **Account codes**: dbt never assumes one. The old `'1800'`/`'1900'`/`'DISPOSAL'`
  constants are gone.

## The manual topside escape hatch

Anything the templates do not produce — an impairment, a step-up without a change of
control, the remeasurement of a retained interest, an audit adjustment to goodwill —
is posted as a manual Consolidation Adjustment (`gold_consolidation_adjustments`,
[Topside Journals](topside-journals.md)). It flows into the same
`gold_fully_consolidated_tb` and is held to the same rule by
`assert_topside_journal_balanced`. A topside booked against `goodwill_account` is
**not** picked up by the disposal journal's goodwill line today (it derecognises what
the ACQ and GWA journals booked); post the counterpart topside in the disposal period.

## Tests and fixtures

| Test | Severity | Proves |
|---|---|---|
| `assert_acquisition_journal_balances` | error | each ACQ `journal_id` sums to 0 per group and period (±0.01) |
| `assert_goodwill_amortisation_journal_balances` | error | the same for GWA |
| `assert_disposal_journal_balances` | error | the same for DSP |
| `assert_acquisition_accounts_declared` | error | one row per submitted deal and missing/invalid policy field or account |
| `assert_bargain_purchase_refused` | error | a bargain under `'Refuse'`, unposted, named |
| `assert_goodwill_calculated` (PRD-11, retargeted) | error | a submitted deal with consideration has a `goodwill` or `bargain_gain` line |
| `assert_disposal_gain_loss_exists` (PRD-12, retargeted) | error | a submitted disposal has a `gain_loss` line (names a retained interest) |
| `assert_cta_recycled_on_disposal` (PRD-12, retargeted) | error | a disposed entity with accumulated CTA has a `cta` line |
| `assert_acquisition_measured_in_period` | warn | net assets would be measured at a period-end later than the acquisition period |
| `assert_end_to_end_bs_balances` (PRD-22) | error | the consolidated balance sheet balances in every period, acquisition and disposal periods included |

Each test is selectable with its own journal: `+gold_business_combination_journal
assert_acquisition_journal_balances`, `+gold_goodwill_amortisation_journal
assert_goodwill_amortisation_journal_balances`, `+gold_business_disposal_journal
assert_disposal_journal_balances` (the disposal journal reads the other two, so its
selector builds all three).

Fixtures under `dbt_project/test_fixtures/` (`ZZ` codes only, see its README):
`business_combination_100pct.sql`, `business_combination_80pct.sql`,
`business_combination_history.sql`, `business_combination_bargain.sql` and
`.refuse.sql`, `business_combination_costs.sql`, `goodwill_amortisation.sql` and
`.disposal.sql`, `business_disposal.sql`, the `*.must_flag.sql` fixtures of the
guards, and `deal_tables_empty.sql` for a `build-live` run before konsol has deployed
the six tables. Because konsol's tables do not exist on a stack until konsol deploys
them, these fixtures `CREATE TABLE IF NOT EXISTS` the deal tables with the exact DDL
before inserting.

## On a stack with deals still on Ownership Periods

konsol's migration turns the Ownership Periods' deal fields into **Draft** Business
Combinations and Disposals. Until an accountant reviews and submits them the deal
tables hold no rows, the three journals are empty, the one-sided rows are gone, and
PRD-22 passes (row J7: 0 unbalanced group-periods on a live clone). Submitting a deal
posts its journal on the next build.
