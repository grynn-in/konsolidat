# Onboarding workbook

An Excel template a group fills in once to stand up konsolidat / konsol: entities, fiscal
calendar, dimensions and reporting hierarchies, the group chart of accounts, intercompany
pairs, the consolidation tree, ownership, governed FX rates and IAS 21 historical rates.
Trial balances follow as one file per period. A script loads all of it into a konsol site
through `frappectl`.

| File | What it is |
|------|------------|
| `Konsolidat_Onboarding_Template.xlsx` | The blank template. One sheet per konsol doctype, header row = fieldnames, hover help on every header, drop-downs for fixed vocabularies, grey example rows (`EXAMPLE_` codes) to delete before loading. |
| `examples/aquila/Aquila_Group_Master_Data.xlsx` | The same workbook filled for the fictional Aquila Group (below). |
| `examples/aquila/tb/TB_FY2025_P12.xlsx` … `TB_FY2026_P11.xlsx` | Its trial balances: the FY2025 year-end balances, then eleven monthly uploads. |
| `konsol_load.py` | Loads a filled workbook and a folder of trial-balance files into a konsol site (`frappectl`). |
| `build_workbooks.py` | Regenerates the template and the example from code; `konsol_template.py` is the sheet schema both scripts share. |

## Quick start

1. Install [`frappectl`](https://github.com/grynn-in/frappectl) (`uv tool install frappectl`) and log a profile in for a user
   with the **EPM Admin** (Close Lead) or System Manager role: `frappectl auth login`.
2. Copy `Konsolidat_Onboarding_Template.xlsx`, fill the sheets in order (the README sheet inside lists them with
   their rules), delete the grey `EXAMPLE_` rows.
3. Put one trial-balance file per period in a folder (CSV or `.xlsx`, data on the first sheet), in the format on the
   `Trial_Balance` sheet. Name them so they sort in period order (`TB_FY2025_P12.xlsx`, `TB_FY2026_P01.xlsx`, …).
4. Dry-run, then load:

   ```bash
   uv run konsol_load.py MyGroup.xlsx --tb-dir tb -s <profile> --dry-run
   uv run konsol_load.py MyGroup.xlsx --tb-dir tb -s <profile>
   ```

5. Apply the published configuration to the warehouse and build: `konsol schema apply --run-dbt` (konsol-cli), or
   submit a Pipeline Run in Desk. Consolidation then runs on the loaded trial balances.

Each sheet is also importable on its own with **Frappe Desk → Data Import** (pick the doctype, upload the sheet):
the header row is the doctype's fieldnames. The loader-only columns (`parent_group`, `parent_member_code`, `journal_ref`, `deal_ref`)
and the child-table sheets the loader nests into their parent (`Fiscal_Periods` into its year; `CJ_Lines` into its journal; `BC_*`
and `BD_Proceeds` into their deal) need the script or a hand edit.

Consolidation Journals, Business Combinations and Business Disposals carry a Frappe Workflow in konsol, so the loader does not
`submit` them: it sends each for approval (`frappe.model.workflow.apply_workflow`) and approves it
(`konsol.close.approval_api.approve`, reason "Onboarding load", which satisfies the self-approval rule). Ownership Periods, FX
rates and Historical Equity Rates are submitted directly.

## What goes where

| Sheet | konsol doctype | Notes |
|-------|----------------|-------|
| `Settings` | EPM Settings | `default_amount_basis`, `tb_accepts_*` flags. |
| `Fiscal_Years`, `Fiscal_Periods` | EPM Fiscal Year (+ periods) | Declare the year-end you start from and the year you upload. Period-end balance files need a Closing period. |
| `Entities` | Entity | Legal entities and management roll-up nodes. `entity_code` is the `data_area_id` on trial balances; `functional_currency` must match every trial-balance row. |
| `Dimensions` | Dimension | `dim_<name>` ticked `in_trial_balance` becomes a trial-balance column of exactly that header. |
| `Reporting_Hierarchies`, `Reporting_Hierarchy_Members` | Reporting Hierarchy (+ Member) | Management trees on a dimension; leaf codes are the dimension values. Published after its members load. |
| `Dimension_Mappings` | Dimension Mapping | Optional, connector-fed entities only. |
| `Main_Accounts` | Main Account | The group chart: headings and posting accounts, each declared (type, statement, normal balance, time balance, fx method), cash-flow category on every balance-sheet posting account, exactly one `is_retained_earnings`. Parents load first. |
| `Intercompany_Accounts` | Intercompany Account | The account pairs consolidation eliminates. Both sides need `allow_ic` on the chart. |
| `IC_Elimination_Rules` | IC Elimination Rule | Optional: unrealised profit in inventory. |
| `Scenarios` | Scenario | Created only when missing (konsol ships defaults). |
| `Consolidation_Groups` | Consolidation Group | Group nodes (blank `data_area_id`, a reporting currency) and entity nodes. Policy and journal accounts on the root only. |
| `Ownership_Periods` | Ownership Period | Dated ownership of every non-root node. Submitted. Optional `owner_entity`: the entity whose node holds the share (blank = the owned node's tree parent, which is the group's own node only for a node directly under it). Two holders of one entity are two rows. |
| `Method_Declarations` | Consolidation Group (`method_declarations` table) | Optional: the method (`full`, `equity` or `none`) for an entity reached by more than one ownership path, with a required `reason`. Merged into the group's own node. |
| `FX_Rates` | Group Exchange Rate | Closing and Average per period, from each entity currency into each group currency. Submitted. |
| `Historical_Equity_Rates` | Historical Equity Rate | Frozen equity rates per foreign entity and equity account. Submitted. |
| `Consolidation_Journals` | Consolidation Journal | Manual consolidation entries the templates do not produce (e.g. the opening elimination of the parent's investments against subsidiaries' share capital). Lines in the group currency, debits = credits; posts as a movement in its period and stays in the balance sheet from then on. `journal_ref` is loader-only and joins `CJ_Lines`. Approved on load through the workflow. |
| `CJ_Lines` | Consolidation Journal Line | The journal's lines (`lines` table): entity, account, debit or credit. |
| `Business_Combinations` | Business Combination | One row per acquisition: root group, acquired entity, acquisition date (first day of a period), share, currency. `deal_ref` is loader-only and joins the three `BC_*` sheets. Submitted; approval creates the entity's Ownership Period, so `Ownership_Periods` carries no row for it. Optional `acquirer_entity`: the entity whose node acquires (blank = the acquired node's tree parent). |
| `BC_Consideration` | Business Combination Consideration | The deal's consideration by component (`consideration` table). At least one row per deal. |
| `BC_Acquired_Balances` | Business Combination Acquired Balance | The acquired balance sheet at the last period-end before the acquisition period (`acquired_balances` table): debit +, credit -, netting to equity; `fair_value_adjustment_total` on the deal must equal the sum of the lines. |
| `BC_Costs` | Business Combination Cost | Acquisition-related costs (`costs` table). |
| `Business_Disposals` | Business Disposal | One row per disposal: root group, disposed entity, disposal date (the Ownership Period's last day), share (full disposals only), currency. `deal_ref` joins `BD_Proceeds`. Submitted; approval ends the Ownership Period on that date. Optional `disposer_entity`: the entity whose node sells (blank = the sold node's tree parent). |
| `BD_Proceeds` | Business Disposal Proceeds | The proceeds by component (`proceeds` table). At least one row per deal. |
| trial-balance files | Trial Balance Upload → Trial Balance Submission | `data_area_id, fiscal_year, fiscal_period, main_account, debit, credit, currency[, description][, partner_data_area_id][, amount_basis][, dim_*…]`. Debits equal credits per entity-period, in the currency's minor unit. |

`owner_entity` (konsol#117) names who holds a share. The loader resolves it to the Consolidation Group node of
(`consolidation_group`, `owner_entity`) and sends `owner_node`; a blank owner is resolved by the loader to the owned
node's tree parent (its `parent_group`; the group's own node only for a node directly under it) and sent the same way.
A period is identified by group, entity, owner node and `effective_date`, so a blank row never matches another holder's
row. A dry run checks `owner_entity` against the workbook's own `Consolidation_Groups` rows and names a missing node.
A journal on `Consolidation_Journals` is identified by group, fiscal year, period and `journal_ref`; the server holds no
reference field, so the loader writes the description as `[journal_ref] text` and finds the journal by that prefix.
The description is free text: rewording it never creates a second journal.

`Method_Declarations` is needed only when an entity is reached by more than one ownership path, or the paths' sum
exceeds 50% without an all-full path: until it is declared the build names the entity in
`assert_method_declared_for_multi_path`. The loader adds each missing (`data_area_id`, `effective_date`) row to the
group's own node in one update, leaves matching rows alone and never deletes. A blank `reason`, a method outside
`full / proportional / equity / none`, or a group without its own node is refused by name; a blank `reason` or an
unknown method stops the run before anything is sent. `proportional` is an IFRS 11 joint operation (konsol#117 pair 3).

The loader is idempotent in the way a person would be: a row whose natural key exists is updated, a submittable row
that already has a live document is left alone, and an entity-period konsol already holds is reported and skipped.
It never deletes. `--only SHEET` / `--skip SHEET` scope a run; `--dry-run` prints every `frappectl` call it would make.

Why `frappectl` and not konsol-cli: since konsol#379, konsol-cli moves only the semantic model (dimensions, measures,
datasets, connectors) as a GitOps bundle and applies the schema. Entities, charts, groups, rates and trial balances
are ordinary documents, which is what `frappectl doc create/update/submit`, `file upload` and `method call` do.

## The Mini Group example

`examples/mini/`: the same workbook with the story cut to the bone. Three legal entities, all in EUR: the parent, one company bought on the first day of Activity, one company sold on the last day of Activity. No financial dimensions, no intercompany, no other currency. The calendar is three periods — Start, Activity, Close. Rebuild: `uv run build_mini.py`. Its README is the arithmetic.

## The Aquila Bike Group example

`examples/aquila-bike/`: the small, fully worked case (10 consolidated EU entities + a 30% associate, five currencies, a 70%
subsidiary, an acquisition on 1 June 2024 and a disposal on 31 December 2024, intercompany on five declared pairs, governed
monthly rates and historical equity rates, three dimensions), with the consolidation also done offline in Excel
(`Aquila_Bike_Walkthrough.xlsx`, live formulas, client talk track) and a Python replica of the warehouse's rules. Its README
is the walkthrough script. Rebuild: `uv run build_aquila_bike.py && python3 aquila_bike_offline.py && uv run build_aquila_bike_walkthrough.py`.

## The Aquila Group example

Fictional, deterministic (a rebuild reproduces it byte for byte in content), and sized like a real mid-cap group:

| | |
|---|---|
| Legal entities | 46 in 22 countries: 26 in the EU (NL, DE, FR, BE, ES, IT, PT, AT, IE, FI, GR, SK, LT, PL, SE, DK, CZ, HU, RO), 5 UK, 7 US, 7 India |
| Currencies | EUR, GBP, USD, INR, PLN, SEK, DKK, CZK, HUF, RON; group reports in EUR, sub-groups in EUR / GBP / USD / INR |
| Consolidation tree | root `AQUILA` → `AQ_EU`, `AQ_UK`, `AQ_US`, `AQ_IN` → entities; minorities at 51 %, 60 %, 74 %, 75 %, 80 %, a 50 % proportional joint operation, a 40 % equity-method associate |
| Chart | 238 accounts (188 posting), 4 levels, IFRS layout, 20 intercompany accounts in 10 pairs, cash-flow categories on every balance-sheet account |
| Dimensions | `dim_business_line`, `dim_cost_center`, `dim_product_group` on the trial balance; `dim_project`, `dim_channel` for budgets; `dim_function` for journals |
| Hierarchies | `DIVISIONS` (Water / Chemical / Institutional / Corporate → sub-divisions), `COST_CENTERS`, `PRODUCT_GROUPS` |
| FX | 216 governed rates: Closing and Average, 9 currencies, FY2025 P12 to FY2026 P11, quoted per 1 / 100 / 1,000 units |
| Trial balances | 12 files, ~8,100 rows each (≈97,700 rows), Period-end balance basis; FY2025 P12 carries the year's P&L in its accounts, FY2026 files carry it in 3300 Retained earnings |
| Intercompany | Management fees, royalties, goods, services, loans with interest and a cash pool; both sides booked at the governed rates, so receivables match payables to the cent after translation and the P&L flows differ only by average-vs-closing |

Every file was checked against konsol's own pure intake rules (header, duplicates, partner, balance in minor
units, dimension columns), the chart against its declaration and publish rules, and the fiscal years against the
calendar rules, with zero problems. The example has not yet been loaded into a live site: the loader's
`frappectl` calls were exercised in `--dry-run` only.

Regenerate after editing the generator:

```bash
uv run build_workbooks.py            # template + example
uv run build_workbooks.py template   # just the blank template
```

## Conventions baked into the template

- Codes are upper case, stable, and are the warehouse join keys. Dates are ISO. Flags are 1/0.
- A trial-balance file declares everything: the entity, the period, the currency on every row, the amount basis, the
  partner on intercompany rows, the dimension values. Nothing is inferred and nothing falls back silently; a refused
  file names the row and the rule.
- Equity accounts translate at the historical rate (IAS 21), balance sheet at closing, P&L at average; the chart says
  which, per account, and a missing rate stops the build by name.
