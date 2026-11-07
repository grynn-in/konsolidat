# Aquila Bike Group — a small, fully worked consolidation

A fictional bicycle group built to show the core of consolidation on one screen: ten consolidated legal
entities in ten EU countries and five currencies, a 30% associate, a 70% subsidiary, one acquisition in
June, one disposal at the year end, intercompany trade, fees, loans and interest on declared account
pairs, governed monthly rates and IAS 21 historical rates, three reporting dimensions. Every number is
deterministic and every number can be traced: the same consolidation is done offline in Excel with live
formulas, replicated in Python from the warehouse's rules, and loaded into a konsol site and built by the
warehouse, and the three agree to the cent (see *Verification* below).

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
| ABSE | Aquila Cykel Sverige AB | SE | SEK | Sales. **Owned 70%**: the non-controlling-interest case |
| ABPL | Aquila Rowery Polska Sp. z o.o. | PL | PLN | Components factory; sells to ABDE, ABIT and (from June) ABCZ |
| ABCZ | Aquila Kola s.r.o. | CZ | CZK | **Acquired 100% on 1 June 2024** for EUR 11.0m: goodwill, fair value step-up on plant, costs expensed |
| ABDK | Aquila Cykler Danmark A/S | DK | DKK | Owned since 2015, **sold 100% on 31 December 2024** for EUR 7.0m: CTA recycled, gain on disposal |
| ABPT | Aquila Bicicletas Portugal Lda | PT | EUR | **30% associate**, equity method |

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
   ABSE at 70% with the 30% visible per row. Show one pair in sheet IC and the CTA grid.
3. **P6, the acquisition.** Sheet Acquisition: the 31 May balance sheet comes in through the journal (line 0), the
   acquired equity is eliminated, the step-up on plant posts, goodwill = consideration − (net assets + step-up), the
   parent's investment is credited, the costs are expensed. ABCZ's own June movements come through the entity layer.
   In konsol: the Business Combination document, Approved; in the warehouse: `gold_business_combination_journal`.
4. **P7–P11.** ABCZ consolidated like everyone else; the management fee to ABCZ starts; its balances retranslate.
5. **P12, the disposal.** Sheet Disposal: ABDK's net assets leave at the December closing rate, its accumulated CTA
   is recycled, the proceeds land on the settlement account, the balancing line is the gain. ABDK's full-year
   result stays in the group result (IFRS 10.B98).
6. **Year end.** Statements sheet: FY2024 P&L and the balance sheet at 31 December, tool view and IFRS view.
7. **Go back to P6, P7.** Every period's movements are kept. In this workbook change the column; in Excel with the
   add-in, `=K.EPM("AQBIKE", 2024, 7, "4110", "consolidated_amount", "consolidated")` reads the live figure
   (sheet LiveCheck).

## The P&L in twelve lines

Three views of the same year, each from `../../aquila_bike_pl.py`, which reads `model/expected.json` (nothing is
typed in; `uv run aquila_bike_pl.py --unit 1` gives the EUR figures). Credit-positive: revenue and profit positive,
costs in brackets. Tool view: subsidiaries at the group's share, so ABSE contributes 70% of every line. The same
168 cells computed from the live warehouse on `demo-ext.konsolidat.com` (`gold_fully_consolidated_tb`, AQBIKE)
agree with these to the cent (7 Nov 2026).

**Before and after consolidation, FY2024** (EUR thousand; costs in brackets)

| Line | Ten entities summed, 100% | Minority's 30% of ABSE | Intercompany eliminations | Deal journals | Equity method | Consolidated FY2024 |
|---|---:|---:|---:|---:|---:|---:|
| Revenue, net of dealer discounts (4110-4220, 4910) | 202,428 | (5,497) | – | – | – | 196,931 |
| Intercompany revenue: goods and management fees (4310, 4340) | 24,493 | – | (24,493) | – | – | – |
| Cost of sales, incl. intercompany purchases and fees (51xx-55xx) | (127,289) | 2,921 | 23,848 | – | – | (100,520) |
| **Gross profit** | **99,632** | **(2,576)** | **(645)** | **–** | **–** | **96,411** |
| Operating expenses net of other income: staff, selling, admin, R&D (61xx-65xx, 67x0 except deals) | (49,436) | 1,349 | – | – | – | (48,087) |
| Depreciation, amortisation, impairment (66xx) | (6,728) | 163 | – | – | – | (6,565) |
| Deal items: acquisition costs (6770), gain on disposal (6730), bargain purchase (6760) | – | – | – | 1,925 | – | 1,925 |
| **Operating profit** | **43,468** | **(1,064)** | **(645)** | **1,925** | **–** | **43,684** |
| Financial items, net, incl. intercompany interest (71xx, 72xx) | (2,374) | 48 | (27) | – | – | (2,353) |
| Share of result of the associate ABPT, 30% (EQ_INCOME) | – | – | – | – | 211 | 211 |
| Income taxes (8xxx) | (9,800) | 209 | – | – | – | (9,590) |
| **Net result for the period (group share)** | **31,294** | **(807)** | **(672)** | **1,925** | **211** | **31,952** |

IFRS 10 view of the same year: total result at 100% 33,430, of which non-controlling interests 807 and owners of the parent 32,623. The owners' result is 672 above the tool's: the minority's 30% of the group's sales, fees and interest to ABSE, which the tool takes out of the P&L and books to NCI equity (3700, decision 12).

**Before and after the acquisition of ABCZ (1 June 2024)** (EUR thousand; costs in brackets)

| Line | P5 (May) consolidated | P6 (June) consolidated | of which ABCZ's own June (entity layer) | of which the acquisition journal |
|---|---:|---:|---:|---:|
| Revenue, net of dealer discounts (4110-4220, 4910) | 21,163 | 23,208 | 1,674 | – |
| Intercompany revenue: goods and management fees (4310, 4340) | – | – | – | – |
| Cost of sales, incl. intercompany purchases and fees (51xx-55xx) | (10,721) | (11,992) | (862) | – |
| **Gross profit** | **10,442** | **11,216** | **812** | **–** |
| Operating expenses net of other income: staff, selling, admin, R&D (61xx-65xx, 67x0 except deals) | (5,074) | (5,605) | (413) | – |
| Depreciation, amortisation, impairment (66xx) | (526) | (562) | (37) | – |
| Deal items: acquisition costs (6770), gain on disposal (6730), bargain purchase (6760) | – | (300) | – | (300) |
| **Operating profit** | **4,842** | **4,748** | **362** | **(300)** |
| Financial items, net, incl. intercompany interest (71xx, 72xx) | (161) | (428) | (7) | – |
| Share of result of the associate ABPT, 30% (EQ_INCOME) | 26 | 25 | – | – |
| Income taxes (8xxx) | (1,152) | (1,123) | (75) | – |
| **Net result for the period (group share)** | **3,554** | **3,223** | **280** | **(300)** |

**Before and after the disposal of ABDK (31 December 2024)** (EUR thousand; costs in brackets)

| Line | P11 (Nov) consolidated | P12 (Dec) consolidated | of which ABDK's own December (entity layer) | of which the disposal journal |
|---|---:|---:|---:|---:|
| Revenue, net of dealer discounts (4110-4220, 4910) | 12,394 | 13,958 | 701 | – |
| Intercompany revenue: goods and management fees (4310, 4340) | – | – | – | – |
| Cost of sales, incl. intercompany purchases and fees (51xx-55xx) | (5,873) | (7,400) | (337) | – |
| **Gross profit** | **6,521** | **6,558** | **364** | **–** |
| Operating expenses net of other income: staff, selling, admin, R&D (61xx-65xx, 67x0 except deals) | (3,080) | (3,484) | (180) | – |
| Depreciation, amortisation, impairment (66xx) | (562) | (562) | (27) | – |
| Deal items: acquisition costs (6770), gain on disposal (6730), bargain purchase (6760) | – | 2,225 | – | 2,225 |
| **Operating profit** | **2,879** | **4,737** | **157** | **2,225** |
| Financial items, net, incl. intercompany interest (71xx, 72xx) | (179) | (200) | (10) | – |
| Share of result of the associate ABPT, 30% (EQ_INCOME) | 18 | 11 | – | – |
| Income taxes (8xxx) | (661) | (559) | (32) | – |
| **Net result for the period (group share)** | **2,056** | **3,989** | **115** | **2,225** |

Reading the three tables:

- **Consolidation** removes the EUR 24.5m the group sold to itself (goods from ABIT and ABPL, management fees from
  ABH) and the matching purchases, takes the minority's 30% of ABSE out of every line, expenses the acquisition
  costs, books the gain on the sale of ABDK and picks up 30% of ABPT's result. The group's revenue to the outside
  world is unchanged by consolidation: the 5.5m drop is ABSE's minority share, not an elimination.
- **Acquisition.** June is the first month ABCZ's own P&L is in the group (its 31 May balance sheet came in through
  the journal, with no P&L). ABCZ adds 1.7m revenue and 0.3m result; the 0.3m of legal and due-diligence costs are
  expensed in the same month (IFRS 3.53), so the group result for June is below May's although revenue is higher.
- **Disposal.** ABDK's December result is still in the group (IFRS 10.B98: consolidated until control is lost, here
  31 December), and the gain on disposal of 2.2m (proceeds 7.0m less net assets of 4.8m at the December closing
  rate, plus 15k of accumulated CTA recycled) lifts the December result to about twice November's. The example ends
  there; from FY2025 ABDK is simply not in the group.

## What the tool does that an IFRS reader should know

Said plainly, because a client who knows IFRS 10 will ask.

- **Subsidiaries are carried at the group's share.** ABSE contributes 70% of every line; the minority's 30% is
  computed per row (`nci_amount`) but the tool's statements have no NCI line (konsolidat#204, open). The
  walkthrough's Statements sheet shows both views and reconciles them; owners' equity is the same in both.
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
  credit income). The warehouse model posted both legs with one sign and untranslated when this was written; the
  fix is on branch `fix-equity-method-journal` and the verification below ran with it.
- **"Yearly rates"** are not a rate type: Group Exchange Rate has Closing and Average per period. The only
  year-wide rate here is the 2023 annual average on FY2023 P12, because the whole FY2023 result sits in that period.

## Verification

Done 7 Nov 2026. Four independent computations of the same group agree to the cent.

- **Generator** (`build_aquila_bike.py`): every entity-period balances to the cent (asserted); 138 entity-periods,
  19,918 rows, 144 accounts, 2 fiscal years pass konsol's own frappe-free intake, chart, calendar and policy rules
  with 0 problems. Rates are declared at the precision konsol stores (exchange-rate quotes 9 decimals, historical
  equity rates 6): declare more and the replica and the warehouse differ by cents on equity.
- **Python replica** (`aquila_bike_offline.py` → `model/expected.json`): every layer of every period nets to zero;
  every intercompany pair matched (472 pairs, 4 cent-level fx differences, nothing in 6750).
- **Excel walkthrough** (`Aquila_Bike_Walkthrough.xlsx`): recalculated in LibreOffice: 357,270 formulas, 0 errors;
  0 cells differ from the replica by 0.01 or more; the tool-view and IFRS-view balance sheets balance in every
  period; the owners'-result reconciliation to the NCI legs is 0 in every period.
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
