# Mini Group — parent, one acquisition, one disposal

The small sibling of [Aquila Bike](../aquila-bike/README.md). Same workbook shape, almost none of the machinery: three legal entities, one currency, no financial dimensions, no intercompany, no minorities, no associate. The calendar is three periods.

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
| HOLD | Mini Holding AG (NL, EUR) | The parent, throughout |
| DSP | Mini Disposed GmbH (DE, EUR) | Owned since 2020. **Sold 100% on 30 December 2025** for EUR 1,000,000 |
| ACQ | Mini Acquired GmbH (DE, EUR) | **Bought 100% on 1 February 2025** for EUR 1,200,000 cash, plus EUR 50,000 of legal fees |

The consolidation tree is flat: `MINI` (EUR) and the three entities under it. There is no management tree and no reporting dimension. Every entity keeps its books in EUR, so there are no FX rates and no historical equity rates.

Policy on the root, the same choices as Aquila Bike, on a 24-account chart (`MINI_GROUP`): IFRS, partial goodwill, impairment only, acquisition costs expensed. Journal accounts 1400 goodwill, 1410 fair value adjustment, 1300 investment, 3700 NCI (unused), 6730 disposal gain or loss, 1500 deal settlement, 6770 acquisition costs, 6750 intercompany differences (unused, tolerance 0). 3300 is the one retained-earnings account. 3100 share capital is `historical`.

## The three periods

Custom calendar, FY2025. Nothing else is declared.

| Period | Code | Type | Dates | What the file is |
|---|---|---|---|---|
| 1 | START | Regular | 1–31 January 2025 | Balance sheets only. The position at the start. |
| 2 | ACT | Regular | 1 February – 30 December 2025 | Period-end balances, with the year's result still in the P&L accounts. |
| 13 | CLS | Closing | 31 December 2025 | The same balance sheets, result closed into 3300. |

`tb_accepts_closing = 1` because Close is a real upload, not a period the warehouse has to invent. There is no later year, and each entity already has a file in the Closing period, so nothing is synthesised on top.

The acquisition is dated **1 February**, the first day of Activity (konsolidat#278: the ownership window tests the period's first day). The balance sheet it measures is Start, the last period-end before that. The disposal is dated **30 December**, the last day of Activity, so the journal lands in Activity and not in Close (a Closing period that shares the date is skipped). DSP's ownership ends that day. Close is the next day, so DSP is no longer in the group when the books close. Its Close file is still there: those are its own books, and leaving it out would make the warehouse read a vanished balance sheet as a movement.

## The figures

Euros. Assets and expenses positive in the text below only where a statement reads that way; the files themselves are debit and credit columns, and every entity-period balances.

### Start — balance sheets

| | HOLD | DSP | ACQ (not yet owned) |
|---|---:|---:|---:|
| Cash (1100) | 2,000,000 | 200,000 | 300,000 |
| Plant (1200) | – | 800,000 | 700,000 |
| Accumulated depreciation (1210) | – | (200,000) | (100,000) |
| Investment in DSP (1300) | 500,000 | – | – |
| Trade receivables (1600) | – | 100,000 | 80,000 |
| Trade payables (2100) | – | (150,000) | (80,000) |
| Share capital (3100) | (1,500,000) | (500,000) | (400,000) |
| Retained earnings (3300) | (1,000,000) | (250,000) | (500,000) |
| **Net assets** | **2,500,000** | **750,000** | **900,000** |

HOLD founded DSP and carries it at the EUR 500,000 it paid in as share capital. DSP's retained earnings of 250,000 are profits since then, so they stay in the group. The opening journal `CJ-OPEN-2025`, posted in Start, is two lines: debit DSP share capital 500,000, credit HOLD's investment 500,000.

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

ACQ, from the day it is bought (its Start file had no P&L):

| | EUR |
|---|---:|
| Revenue | 250,000 |
| Cost of sales | (100,000) |
| Operating expenses | (40,000) |
| Depreciation | (20,000) |
| Tax | (20,000) |
| **Result** | **70,000** |

HOLD spends 80,000 and does the two deals. Cash walks 2,000,000 − 80,000 − 1,200,000 − 50,000 + 1,000,000 = **1,670,000**. The investment account becomes 500,000 + 1,200,000 = **1,700,000**. The deal settlement account (1500) holds the fees as a debit and the proceeds as a credit: 50,000 − 1,000,000 = **(950,000)**.

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
| DSP | 90,000 | 340,000, was 250,000 |
| ACQ | 70,000 | 570,000, was 500,000 |

DSP's Close file is its own books only. Ownership ended on 30 December, so the group balance sheet at Close is HOLD and ACQ.

## What was left out on purpose

- No `dim_*` columns, and the dimension, hierarchy and mapping sheets are empty.
- No second consolidation group, no management roll-up on Entities.
- No intercompany pairs, no loans, no fees.
- No other currency, so no `FX_Rates` and no `Historical_Equity_Rates`.
- No non-controlling interest and no associate. 3700 is on the chart because the policy names it, and it is unused.
- No offline replica and no walkthrough workbook. The arithmetic above is the whole model.
