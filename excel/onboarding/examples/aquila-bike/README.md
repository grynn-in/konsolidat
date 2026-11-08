# Aquila Bike Group — a small, fully worked consolidation

A fictional bicycle group built to show the core of consolidation on one screen: ten consolidated legal
entities in ten EU countries and five currencies (nine at 1 January: ABCZ joins in June, ABDK leaves on
31 December), a 30% associate, a joint venture held 30% + 30% through two group entities, a 70% subsidiary,
one acquisition in June, one disposal at the year end, intercompany trade, fees, loans and interest on declared account
pairs, governed monthly rates and IAS 21 historical rates, three reporting dimensions. Every number is
deterministic and every number can be traced: the same consolidation is done offline in Excel with live
formulas, replicated in Python from the warehouse's rules, and loaded into a konsol site and built by the
warehouse, and the three agree to the cent (see *Verification* below).

Standards the example exercises: IFRS 3 (acquisition method, goodwill, costs expensed, 3.53), IFRS 10 (consolidation,
non-controlling interests, the presumption of control B35, disposal B98), IFRS 11.7 (joint control), IAS 28 (equity
method), IAS 21 (translation, CTA, recycling on disposal, 21.48).

| File | What it is |
|---|---|
| `Aquila_Bike_Master_Data.xlsx` | The filled onboarding workbook: calendar, entities, dimensions and hierarchies, the group chart, intercompany pairs, consolidation tree, ownership, FX and historical rates, the opening consolidation journal, the acquisition and the disposal. Loaded with `konsol_load.py`. |
| `tb/TB_FY2023_P12.xlsx` … `tb/TB_FY2024_P12.xlsx` | 13 bulk trial-balance files on the Period-end balance basis. FY2023 P12 is the opening year end (the FY2023 result still in its P&L accounts). ABCZ appears from FY2024 P05, ABDK through P12. |
| `Aquila_Bike_Walkthrough.xlsx` | The consolidation done offline in Excel, step by step, with live formulas and a talk track (sheet *Walkthrough*). The Python replica's figures sit beside the formulas as a check column. |
| `model/inputs.json`, `model/expected.json` | What the generator produced and what the Python replica computes from it (every layer of the consolidated trial balance per period). |
| `../../build_aquila_bike.py` | Regenerates the master workbook and the trial balances. `../../aquila_bike_offline.py` recomputes `expected.json`; `../../build_aquila_bike_walkthrough.py` rebuilds the Excel; `../../aquila_bike_pl.py` prints the twelve-line P&L tables below. |

## The group

| Code | Entity | Country | Currency | Role in the story |
|---|---|---|---|---|
| ABH | Aquila Bike Holding N.V. | NL | EUR | Parent. Charges a 1.5% management fee, lends to ABSE (SEK) and ABPL (PLN) |
| ABDE | Aquila Bikes Deutschland GmbH | DE | EUR | Assembly and sales; buys frames from ABIT and components from ABPL |
| ABIT | Aquila Cicli Italia S.r.l. | IT | EUR | Frame factory; sells to ABDE, ABFR, ABSE, ABAT |
| ABFR | Aquila Velo France SAS | FR | EUR | Sales, service and rental |
| ABAT | Aquila Bikes Austria GmbH | AT | EUR | Sales |
| ABES | Aquila Bicicletas Espana S.L. | ES | EUR | Service and rental |
| ABSE | Aquila Cykel Sverige AB | SE | SEK | Sales. **Owned 70%**, carried at 100% with the minority as one NCI line: the non-controlling-interest case |
| ABPL | Aquila Rowery Polska Sp. z o.o. | PL | PLN | Components factory; sells to ABDE, ABIT and (from June) ABCZ |
| ABCZ | Aquila Kola s.r.o. | CZ | CZK | **Acquired 100% on 1 June 2024** for EUR 11.0m: goodwill, fair value step-up on plant, costs expensed |
| ABDK | Aquila Cykler Danmark A/S | DK | DKK | Owned since 2015, **sold 100% on 31 December 2024** for EUR 7.0m: CTA recycled, gain on disposal |
| ABPT | Aquila Bicicletas Portugal Lda | PT | EUR | **30% associate**, equity method |
| ABJV | Aquila Shared Mobility B.V. | NL | EUR | **Joint venture**: 30% held by ABDE and 30% by ABFR (60% in all), equity method on the group's declaration (IFRS 11.7); first trial balance FY2024 P1 |

That is twelve entities: ten consolidated line by line (ABH ... ABDK, ABCZ and ABDK for part of the year), one associate
(ABPT) and one joint venture (ABJV).

Divisions (dimension `dim_business_line`, hierarchy DIVISIONS): Bikes (e-bikes, classic bikes), Components and
services (components and accessories, service and rental), Corporate (the holding's own costs). Also on every
trial-balance row: `dim_cost_center` (COST_CENTERS) and `dim_product_group` (PRODUCT_GROUPS). The Entity
management tree groups the legal entities by sub-division; the consolidation tree is flat under `AQBIKE` (EUR).

Chart: 144 accounts in the aquila numbering (`AQBIKE_GROUP`), every P&L account `average`, every balance-sheet
account `closing`, share capital and premium `historical`, 3300 the one retained-earnings account. Policy on the
root: IFRS, partial goodwill, impairment only, acquisition costs expensed, 12-month measurement period, bargain
purchases recognised; journal accounts 1121 goodwill, 1125 FVA, 1141 investment, 3700 NCI, 6730 disposal gain or
loss, 1235 deal settlement, 6770 acquisition costs, 6750 intercompany differences (tolerance EUR 500).

Intercompany pairs: 1222/2212 trade, 1161/2114 loans, 4310/5410 goods, 4340/5440 management fees, 7120/7220 interest.
Both sides are booked at the governed rates (monthly Average for flows, Closing for balances), so after translation
every pair matches to the cent and the difference account stays empty.

## The walkthrough (what to show, in order)

1. **1 January 2024.** The FY2023 P12 files are the opening position. The warehouse closes the FY2023 result to
   retained earnings in the Closing period 2023-13, at the 2023 annual average rate declared on FY2023 P12. The
   holding's investments in its (founded) subsidiaries are eliminated against their share capital and premium by
   the opening consolidation journal CJ-OPEN-2023 (Consolidation_Journals / CJ_Lines). Consolidated balance sheet
   at 1 January: Statements sheet, column 2023-13.
2. **P1–P5.** A month at a time: balance sheets at the month's closing rate (balances restated, difference in CTA),
   P&L at the month's average rate, share capital at historical rates. Intercompany pairs matched and eliminated;
   ABSE at 100% and its minority attributed by a journal each month (sheet NCI attribution); the joint venture ABJV
   picked up at 60% (sheet Joint venture ABJV). Show one pair in sheet IC (eliminated in full) and the CTA grid.
3. **P6, the acquisition.** Sheet Acquisition: the 31 May balance sheet comes in through the journal (line 0), the
   acquired equity is eliminated, the step-up on plant posts, goodwill = consideration − (net assets + step-up), the
   parent's investment is credited, the costs are expensed. ABCZ's own June movements come through the entity layer.
   In konsol: the Business Combination document, Approved; in the warehouse: `gold_business_combination_journal`.
4. **P7–P11.** ABCZ consolidated like everyone else; the management fee to ABCZ starts; its balances retranslate.
5. **P12, the disposal.** Sheet Disposal: ABDK's net assets leave at the December closing rate, its accumulated CTA
   is recycled, the proceeds land on the settlement account, the balancing line is the gain. ABDK's full-year
   result stays in the group result (IFRS 10.B98).
6. **Year end.** Statements sheet: FY2024 P&L and the balance sheet at 31 December, one view: every subsidiary
   at 100%, the NCI line, and the note on how the tool computes it.
7. **Go back to P6, P7.** Every period's movements are kept. In this workbook change the column; in Excel with the
   add-in, `=K.EPM("AQBIKE", 2024, 7, "4110", "consolidated_amount", "consolidated")` reads the live figure
   (sheet LiveCheck).

## The P&L in twelve lines

Three views of the same year, each from `../../aquila_bike_pl.py`, which reads `model/expected.json` (nothing is
typed in; `uv run aquila_bike_pl.py --unit 1` gives the EUR figures). Credit-positive: revenue and profit positive,
costs in brackets. Subsidiaries are at 100%, so ABSE contributes every line in full; the minority's 30% of its result
is shown beneath the net result as "attributable to non-controlling interests", not taken out of the lines. The twelve
lines are unchanged in number; their figures moved when the rules changed (7-8 Nov 2026, konsolidat#204 option (a)).
The figures below come from the replica; the live warehouse has not been re-run on the new rules (see *Verification*).

**Before and after consolidation, FY2024** (EUR thousand; costs in brackets)

| Line | Entities at 100% | Intercompany eliminations | Deal journals | Equity method (ABPT, ABJV) | Consolidated FY2024 |
|---|---:|---:|---:|---:|---:|
| Revenue, net of dealer discounts (4110-4220, 4910) | 202,428 | – | – | – | 202,428 |
| Intercompany revenue: goods and management fees (4310, 4340) | 24,493 | (24,493) | – | – | – |
| Cost of sales, incl. intercompany purchases and fees (51xx-55xx) | (127,289) | 24,493 | – | – | (102,796) |
| **Gross profit** | **99,632** | **–** | **–** | **–** | **99,632** |
| Operating expenses net of other income: staff, selling, admin, R&D (61xx-65xx, 67x0 except deals) | (49,436) | – | – | – | (49,436) |
| Depreciation, amortisation, impairment (66xx) | (6,728) | – | – | – | (6,728) |
| Deal items: acquisition costs (6770), gain on disposal (6730), bargain purchase (6760) | – | – | 1,925 | – | 1,925 |
| **Operating profit** | **43,468** | **–** | **1,925** | **–** | **45,393** |
| Financial items, net, incl. intercompany interest (71xx, 72xx) | (2,374) | – | – | – | (2,374) |
| Share of result of the associate ABPT, 30%, and the joint venture ABJV, 60% (EQ_INCOME) | – | – | – | 650 | 650 |
| Income taxes (8xxx) | (9,800) | – | – | – | (9,800) |
| **Net result for the period (100%)** | **31,294** | **–** | **1,925** | **650** | **33,869** |

Attributable to: non-controlling interests 807 and owners of the parent 33,063, of a total result of 33,869 at 100%. The NCI amount is 30% of ABSE's own result, posted to 3700 by the attribution journal (intercompany eliminations are in full, so no NCI leg is taken out of any line).

**Before and after the acquisition of ABCZ (1 June 2024)** (EUR thousand; costs in brackets)

| Line | P5 (May) consolidated | P6 (June) consolidated | of which ABCZ's own June (entity layer) | of which the acquisition journal |
|---|---:|---:|---:|---:|
| Revenue, net of dealer discounts (4110-4220, 4910) | 21,797 | 23,851 | 1,674 | – |
| Intercompany revenue: goods and management fees (4310, 4340) | – | – | – | – |
| Cost of sales, incl. intercompany purchases and fees (51xx-55xx) | (10,988) | (12,255) | (862) | – |
| **Gross profit** | **10,809** | **11,596** | **812** | **–** |
| Operating expenses net of other income: staff, selling, admin, R&D (61xx-65xx, 67x0 except deals) | (5,228) | (5,763) | (413) | – |
| Depreciation, amortisation, impairment (66xx) | (539) | (576) | (37) | – |
| Deal items: acquisition costs (6770), gain on disposal (6730), bargain purchase (6760) | – | (300) | – | (300) |
| **Operating profit** | **5,042** | **4,957** | **362** | **(300)** |
| Financial items, net, incl. intercompany interest (71xx, 72xx) | (163) | (430) | (7) | – |
| Share of result of the associate ABPT, 30%, and the joint venture ABJV, 60% (EQ_INCOME) | 64 | 73 | – | – |
| Income taxes (8xxx) | (1,177) | (1,150) | (75) | – |
| **Net result for the period (100%)** | **3,766** | **3,451** | **280** | **(300)** |

**Before and after the disposal of ABDK (31 December 2024)** (EUR thousand; costs in brackets)

| Line | P11 (Nov) consolidated | P12 (Dec) consolidated | of which ABDK's own December (entity layer) | of which the disposal journal |
|---|---:|---:|---:|---:|
| Revenue, net of dealer discounts (4110-4220, 4910) | 12,713 | 14,328 | 701 | – |
| Intercompany revenue: goods and management fees (4310, 4340) | – | – | – | – |
| Cost of sales, incl. intercompany purchases and fees (51xx-55xx) | (5,984) | (7,576) | (337) | – |
| **Gross profit** | **6,730** | **6,752** | **364** | **–** |
| Operating expenses net of other income: staff, selling, admin, R&D (61xx-65xx, 67x0 except deals) | (3,164) | (3,571) | (180) | – |
| Depreciation, amortisation, impairment (66xx) | (576) | (575) | (27) | – |
| Deal items: acquisition costs (6770), gain on disposal (6730), bargain purchase (6760) | – | 2,225 | – | 2,225 |
| **Operating profit** | **2,990** | **4,830** | **157** | **2,225** |
| Financial items, net, incl. intercompany interest (71xx, 72xx) | (181) | (202) | (10) | – |
| Share of result of the associate ABPT, 30%, and the joint venture ABJV, 60% (EQ_INCOME) | 49 | 46 | – | – |
| Income taxes (8xxx) | (676) | (568) | (32) | – |
| **Net result for the period (100%)** | **2,182** | **4,105** | **115** | **2,225** |

Reading the three tables:

- **Consolidation** removes the EUR 24.5m the group sold to itself (goods from ABIT and ABPL, management fees from
  ABH) and the matching purchases, in full: ABSE's trade with the group is eliminated at 100%, so gross profit is the
  same before and after. It then expenses the acquisition costs, books the gain on the sale of ABDK, and picks up
  30% of ABPT's result and 60% of ABJV's (EUR 0.65m together). Revenue to the outside world is the full 202.4m:
  nothing is taken out for the minority.
- **Acquisition.** June is the first month ABCZ's own P&L is in the group (its 31 May balance sheet came in through
  the journal, with no P&L). ABCZ adds 1.7m revenue and 0.3m result; the 0.3m of legal and due-diligence costs are
  expensed in the same month (IFRS 3.53), so the group result for June is below May's although revenue is higher.
- **Disposal.** ABDK's December result is still in the group (IFRS 10.B98: consolidated until control is lost, here
  31 December), and the gain on disposal of 2.2m (proceeds 7.0m less net assets of 4.8m at the December closing
  rate, plus 15k of accumulated CTA recycled) lifts the December result to about twice November's. The example ends
  there; from FY2025 ABDK is simply not in the group.

## What the tool does that an IFRS reader should know

Said plainly, because a client who knows IFRS 10 will ask.

- **Non-controlling interests are one line, computed by a journal.** ABSE is carried at 100% line by line
  (konsolidat#204 option (a)). The minority's 30% is account 3700. It is opened by the opening consolidation journal
  (Cr 3700 1,197,277.20 and Dr 3300 216,000.00, the minority's share of opening retained earnings at the FY2023 P12
  closing rate) and fed each period by the attribution journal NCI-AQBIKE-ABSE-<year>-P<n>: Dr retained earnings
  for 30% of ABSE's result, Dr CTA for 30% of its CTA movement, Cr 3700. At 2024-12 the NCI is 1,197,277.20 +
  1,555,383.38 = 2,752,660.58, which is 30% of ABSE's net assets at the closing rate. Intercompany eliminations are in
  full, with no NCI leg. The walkthrough's Statements sheet shows one view and a note on this; the NCI attribution sheet
  lists the journals.
- **A joint venture is declared, not inferred.** ABJV is reached along two paths (ABDE 30% and ABFR 30%) that add to
  60% with no all-full path, past the 50% presumption of control (IFRS 10.B35). The percentage decides nothing: the
  group declares the method for ABJV (`Method_Declarations`: equity from 2024-01-01, "joint control under the
  shareholders' agreement (IFRS 11.7); 60% does not give control"). Without that row the build fails
  `assert_method_declared_for_multi_path` naming AQBIKE and ABJV, and the method resolves to `none`: nothing is
  consolidated and nothing is picked up. ABDE and ABFR each carry their stake at cost, Dr 1142 / Cr 1241 210,000.00
  in FY2024 P1; the group's pickup is 60% of ABJV's result (EUR 0.44m for FY2024).
- **Year-end close of journal-layer P&L is not done yet** (konsolidat#316). The warehouse closes entity P&L to retained
  earnings in the Closing period, but not the P&L that journals post, such as the equity-method pickup. An associate's
  pickup excludes the year-end close rows, so ABPT has no pickup in 2023-13, and its FY2023 pickup (EUR 0.20m) stays
  in the P&L accounts. The Statements sheet carries it on the line "Result not yet closed".
- **Deals are dated on the first day of a period** (konsolidat#278: the ownership window tests the period's first
  day) and the acquired balance sheet is the last period-end before the acquisition period (konsol#406: konsol's
  "Get Balances" reads one period too far). The example does both; the opening balances it enters are frozen at
  the June closing rate and never retranslated, as the warehouse does.
- **Deal cash goes through the Deal Settlement Account (1235).** The parent books Dr investment / Cr cash on
  acquisition and parks deal costs and disposal proceeds on 1235; the journals clear it. No template eliminates a
  parent's own gain on disposal, so the parent keeps the investment at cost in its own books.
- **An acquired entity's opening intercompany balances are not seen by the pair matching** (the acquisition journal
  brings the balance sheet in as a whole). The example settles the pre-acquisition trade between ABPL and ABCZ on
  completion, as completion accounts usually do, so no artificial difference appears.
- **The equity method** entry is shown as it must be (share of result at the average rate, debit investment /
  credit income), for the associate ABPT and the joint venture ABJV. The warehouse model posted both legs with one
  sign and untranslated when this was written; the fix is on branch `fix-equity-method-journal`.
- **"Yearly rates"** are not a rate type: Group Exchange Rate has Closing and Average per period. The only
  year-wide rate here is the 2023 annual average on FY2023 P12, because the whole FY2023 result sits in that period.

## Verification

Done 7 Nov 2026; the Excel bullet re-run 8 Nov 2026 on the new rules. Four independent computations of the same group agreed to the cent on the
rules of 7 Nov. The **live** run below has not been repeated on the rules of 7-8 Nov (option (a), ABJV): until it is, the replica and
the Excel agree with each other, not yet with the warehouse.

- **Generator** (`build_aquila_bike.py`): every entity-period balances to the cent (asserted); 138 entity-periods,
  19,918 rows, 144 accounts, 2 fiscal years pass konsol's own frappe-free intake, chart, calendar and policy rules
  with 0 problems. Rates are declared at the precision konsol stores (exchange-rate quotes 9 decimals, historical
  equity rates 6): declare more and the replica and the warehouse differ by cents on equity.
- **Python replica** (`aquila_bike_offline.py` → `model/expected.json`): every layer of every period nets to zero;
  every intercompany pair matched (472 pairs, 4 cent-level fx differences, nothing in 6750).
- **Excel walkthrough** (`Aquila_Bike_Walkthrough.xlsx`): recalculated in LibreOffice (8 Nov 2026, rules of 7-8 Nov):
  374,217 formulas, 0 errors; 0 cells differ from the replica by 0.01 or more; the balance sheet balances in every
  period; the NCI closing equals 30% of ABSE's net assets; the opening journal equals `inputs.json`; the ABJV pickup
  and the holders' cost agree. `tests/test_aquila_bike_walkthrough.py` runs the builder and reads every check cell.
- **Live** (`demo-ext.konsolidat.com`, a fresh konsol v16 site, second stack on the demo server): master data,
  deals and the opening journal loaded with `konsol_load.py` (Close Settings `self_approval = Allowed with reason`,
  approvals through konsol's approval API with a reason), the 13 trial-balance files uploaded through the bulk
  loader (138 entity-periods, 0 failed), the Build Approvals approved, dbt built by konsol's own pipeline
  (61 s, 0 errors, 1 warning: `assert_declared_historical_has_a_rate` names the six EUR entities, which need no
  historical rate). `gold_fully_consolidated_tb` for AQBIKE, summed per (fiscal year, period, account, layer):
  **1,512 cells compared with `expected.json`, 0 differences of 0.01 or more.** The warehouse's own per-period
  nets are within ±0.07 (Float64 sums of 20,244 rows); the replica's are exactly 0.

What the live run found (all recorded in `../../HANDOFF.md`): historical equity rates are kept with 6 decimals;
`Dimension.source_column` must repeat the dimension name on an upload-only site; a draft journal left in
Pending Approval must not be sent for approval again; `konsol.tb_bulk.get_upload` is GET-only; back-to-back
bulk loads can deadlock (MariaDB 1213) and are retried once; the acquired balance sheet is the last
pre-acquisition period-end (konsol#406); deals are dated on a period's first day (konsolidat#278).
