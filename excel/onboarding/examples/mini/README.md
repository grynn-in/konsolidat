# Mini Group — a holding company, two companies held throughout, one bought, one sold

The small sibling of [Aquila Bike](../aquila-bike/README.md). Same workbook shape, almost none of the machinery: five legal entities, one currency, no financial dimensions, no intercompany, no minorities, no associate. The calendar is three periods.

| File | What it is |
|---|---|
| `Mini_Master_Data.xlsx` | The filled onboarding workbook. Loaded with `konsol_load.py`. |
| `tb/TB_FY2025_P01_START.xlsx` | Start. Opening balance sheets. |
| `tb/TB_FY2025_P02_ACT.xlsx` | Activity. The year's trading, result still in the P&L. |
| `tb/TB_FY2025_P13_CLS.xlsx` | Close. That result moved into retained earnings. |
| `../../build_mini.py` | Regenerates the workbook and the three files. The figures below are the constants in that script. |

```bash
uv run build_mini.py
uv run konsol_load.py examples/mini/Mini_Master_Data.xlsx --tb-dir examples/mini/tb -s <frappectl profile>
```

## Who is in the group

| Code | Entity | In the group |
|---|---|---|
| HOLD | Mini Holding AG (NL, EUR) | The holding company, throughout. Its own books, no revenue. It holds the others |
| SVC | Mini Services B.V. (NL, EUR) | Held 100% by HOLD since 2020, throughout. A services company |
| PRT | Mini Parts GmbH (DE, EUR) | Held 100% by HOLD since 2020, throughout. A parts company, with plant |
| DSP | Mini Disposed GmbH (DE, EUR) | Held by HOLD since 2020. **Sold by HOLD, 100% on 30 December 2025** for EUR 1,000,000 |
| ACQ | Mini Acquired GmbH (DE, EUR) | **Bought by HOLD, 100% on 1 February 2025** for EUR 1,200,000 cash, plus EUR 50,000 of legal fees |

The consolidation tree is flat: `MINI` (EUR) and the five entities directly under it. Ownership does not follow the tree. It runs through the links: `Ownership_Periods` names HOLD as the owner of DSP, SVC and PRT (`owner_entity`), HOLD's own row has a blank owner and so is held by `MINI`, and the two deals name HOLD as acquirer and seller (`acquirer_entity`, `disposer_entity`). The closure walks owner to owned, so MINI → HOLD → SVC is one path at 100%. There is no management tree and no reporting dimension. Every entity keeps its books in EUR, so there are no FX rates and no historical equity rates.

Policy on the root, the same choices as Aquila Bike, on a 24-account chart (`MINI_GROUP`): IFRS, partial goodwill, impairment only, acquisition costs expensed. Journal accounts 1400 goodwill, 1410 fair value adjustment, 1300 investment, 3700 NCI (unused), 6730 disposal gain or loss, 1500 deal settlement, 6770 acquisition costs, 6750 intercompany differences (unused, tolerance 0). 3300 is the one retained-earnings account. 3100 share capital is `historical`.

### What HOLD is

HOLD is a holding company with its own books: it holds shares and some cash, and earns no revenue. It is consolidated at 100% like the others. `MINI` is the consolidation entity: it has no books of its own and exists to carry the policy and the roll-up. So the group owns HOLD, and HOLD owns the rest.

### Real sale, not a carve-out

DSP is sold as a company: HOLD sells 100% of the shares, and the whole of DSP's balance sheet is derecognised. A carve-out, where a business is sold out of an entity that stays in the group, is not modelled here.

## The three periods

Custom calendar, FY2025. Nothing else is declared.

| Period | Code | Type | Dates | What the file is |
|---|---|---|---|---|
| 1 | START | Regular | 1–31 January 2025 | Balance sheets only. The position at the start. |
| 2 | ACT | Regular | 1 February – 31 December 2025 | Period-end balances, with the year's result still in the P&L accounts. |
| 13 | CLS | Closing | 31 December 2025 (the same day as Activity's last; konsol requires the last Regular period to end on the year end and the Closing period to be that one day) | The same balance sheets, result closed into 3300. |

`tb_accepts_closing = 1` because Close is a real upload, not a period the warehouse has to invent. There is no later year, and each entity already has a file in the Closing period, so nothing is synthesised on top.

The acquisition is dated **1 February**, the first day of Activity (konsolidat#278: the ownership window tests the period's first day). The balance sheet it measures is Start, the last period-end before that. The disposal is dated **30 December**, the last day of Activity, so the journal lands in Activity and not in Close (a Closing period that shares the date is skipped). DSP's ownership ends that day. Close is the next day, so DSP is no longer in the group when the books close. Its Close file is still there: those are its own books, and leaving it out would make the warehouse read a vanished balance sheet as a movement.

## The figures

Euros. Assets and expenses positive in the text below only where a statement reads that way; the files themselves are debit and credit columns, and every entity-period balances.

### Start — balance sheets

| | HOLD | SVC | PRT | DSP | ACQ (not yet owned) |
|---|---:|---:|---:|---:|---:|
| Cash (1100) | 1,700,000 | 300,000 | 150,000 | 200,000 | 300,000 |
| Plant (1200) | – | – | 400,000 | 800,000 | 700,000 |
| Accumulated depreciation (1210) | – | – | (100,000) | (200,000) | (100,000) |
| Investments (1300) | 800,000 | – | – | – | – |
| Trade receivables (1600) | – | 100,000 | 60,000 | 100,000 | 80,000 |
| Trade payables (2100) | – | (120,000) | (90,000) | (150,000) | (80,000) |
| Share capital (3100) | (1,500,000) | (100,000) | (200,000) | (500,000) | (400,000) |
| Retained earnings (3300) | (1,000,000) | (180,000) | (220,000) | (250,000) | (500,000) |
| **Net assets** | **2,500,000** | **280,000** | **420,000** | **750,000** | **900,000** |

HOLD founded DSP, SVC and PRT and carries each at cost in 1300, which is the share capital it paid in: 500,000 + 100,000 + 200,000 = 800,000. It paid for SVC and PRT out of cash, so its Start cash is 1,700,000 (2,000,000 less 300,000); its own share capital and retained earnings are unchanged. Each company's retained earnings are profits since then, so they stay in the group. The opening journal `CJ-OPEN-2025`, posted in Start, is six lines: debit each of DSP, SVC and PRT share capital (500,000, 100,000, 200,000), credit HOLD's investment by the same three amounts.

### Activity — what happened

DSP, for the year, consolidated up to the day it is sold:

| | EUR |
|---|---:|
| Revenue (4100) | 400,000 |
| Cost of sales (5100) | (180,000) |
| Operating expenses (6100) | (70,000) |
| Depreciation (6600) | (30,000) |
| Tax (8100) | (30,000) |
| **Result** | **90,000** |

Cash becomes 320,000 (the 90,000 result plus the 30,000 of depreciation). Net assets at the sale: 840,000.

SVC and PRT, held throughout:

| | SVC | PRT |
|---|---:|---:|
| Revenue (4100) | 300,000 | 220,000 |
| Cost of sales (5100) | (120,000) | (100,000) |
| Operating expenses (6100) | (90,000) | (40,000) |
| Depreciation (6600) | – | (20,000) |
| Tax (8100) | (30,000) | (20,000) |
| **Result** | **60,000** | **40,000** |

SVC's cash becomes 360,000 (300,000 plus the result). PRT's becomes 210,000 (150,000 plus the 40,000 result and the 20,000 of depreciation). Net assets at Close: SVC 340,000, PRT 460,000.

ACQ, from the day it is bought (its Start file had no P&L):

| | EUR |
|---|---:|
| Revenue | 250,000 |
| Cost of sales | (100,000) |
| Operating expenses | (40,000) |
| Depreciation | (20,000) |
| Tax | (20,000) |
| **Result** | **70,000** |

HOLD spends 80,000 and does the two deals. Cash walks 1,700,000 − 80,000 − 1,200,000 − 50,000 + 1,000,000 = **1,370,000**. The investment account becomes 800,000 + 1,200,000 = **2,000,000**. The deal settlement account (1500) holds the fees as a debit and the proceeds as a credit: 50,000 − 1,000,000 = **(950,000)**.

### The acquisition (1 February)

Measured on ACQ's Start balance sheet. Net assets 900,000. Plant stepped up by 100,000, so fair value of net assets is 1,000,000. Price 1,200,000. **Goodwill 200,000.** The legal fees of 50,000 are expensed (6770), not added to goodwill. There is no minority.

The parent's own books already show the cash out: debit investment 1,200,000, debit deal settlement 50,000. The combination journal clears both.

### The disposal (30 December)

Proceeds 1,000,000 against DSP's net assets of 840,000. No goodwill, no fair value adjustment, no currency translation difference. **Gain on disposal 160,000** (6730). DSP's result of 90,000 for the year stays in the group result. The proceeds sit on 1500 in HOLD's books; the disposal journal clears that account. HOLD does not write its investment in DSP out of its own ledger — same convention as Aquila Bike, because no template removes a parent's own gain.

### Close — 31 December

Each company moves its result into retained earnings. Nothing else changes.

| | Result in Activity | Retained earnings after Close |
|---|---:|---:|
| HOLD | (80,000) | 920,000, was 1,000,000 |
| SVC | 60,000 | 240,000, was 180,000 |
| PRT | 40,000 | 260,000, was 220,000 |
| DSP | 90,000 | 340,000, was 250,000 |
| ACQ | 70,000 | 570,000, was 500,000 |

DSP's Close file is its own books only. Ownership ended on 30 December, so the group balance sheet at Close is HOLD, SVC, PRT and ACQ.

The group at Close, in euros:

| | EUR |
|---|---:|
| Group cash at Close | 2,330,000 |
| Owners' equity at Close | 3,440,000 |

Cash is HOLD 1,370,000 + SVC 360,000 + PRT 210,000 + ACQ 390,000. Owners' equity is the group's net assets: those four companies' own net assets (HOLD's investments and the deal settlement account excluded, as the consolidation eliminates them), plus goodwill 200,000 and the plant step-up 100,000. Cross-check from the other side: HOLD's 1,500,000 share capital, plus retained earnings 920,000 + 240,000 + 260,000, plus ACQ's 70,000 since it was bought, plus DSP's 340,000 (250,000 before and 90,000 during, which stay in the group), plus the gain of 160,000, less the 50,000 of fees, is 3,440,000. The pre-group retained earnings of DSP, SVC and PRT stay in the group, as the opening journal eliminates only their share capital against HOLD's cost.

## What was left out on purpose

- No `dim_*` columns, and the dimension, hierarchy and mapping sheets are empty.
- No second consolidation group, no management roll-up on Entities.
- No intercompany pairs, no loans, no fees.
- No other currency, so no `FX_Rates` and no `Historical_Equity_Rates`.
- No carve-out of a business out of an entity that stays in the group.
- No non-controlling interest and no associate. 3700 is on the chart because the policy names it, and it is unused.
- No offline replica and no walkthrough workbook. The arithmetic above is the whole model.
