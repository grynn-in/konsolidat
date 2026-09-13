# Reporting Hierarchies Guide

A **Reporting Hierarchy** is a management tree over one dimension, for example business unit. It answers questions such as "what did the DACH region sell?", where DACH is a heading you invent and the region is made of business units that several companies post to. You build the tree in konsol and read any node of it from Excel with `K.EPM`.

## What a Reporting Hierarchy Is

- **One dimension per tree.** A tree is built on one published dimension, such as `dim_business_unit`. Several trees may use the same dimension.
- **Leaves are real codes.** A leaf's Member Code must match the dimension code on the postings exactly (for example `BU_AT01`).
- **Groups are headings.** A group (for example `DACH` or `EUROPE`) holds nothing of its own. It adds up the leaves below it.
- **Every node holds the sum of the leaves below it.** When a tree is published, the warehouse precomputes a total for every node: actuals, budget and forecast (with their layers), and variance.
- **Status.** A tree is **Draft**, **Published** or **Inactive**. Only a Published tree can be read from Excel.
- **Default Hierarchy.** One tree per dimension may be marked default. Its only job is a completeness check: the warehouse lists the dimension codes that appear on postings but are missing from the default tree. The check runs only while the default tree is Published. The default plays no part in choosing a tree for a formula.

A code that is not placed in a tree is not in any of its nodes, so a tree's top node is not automatically "the whole company". The default tree's completeness check (which runs only while the default tree is Published) is how codes you have not placed are found.

### How It Differs from a Consolidation Group

| | Consolidation Group | Reporting Hierarchy |
|---|---|---|
| Rolls up | Legal entities | Codes of one dimension, across entities |
| Intercompany eliminations | Yes | **No** |
| Ownership and NCI | Yes | No |
| Currency translation | Yes, into the group's reporting currency | No: amounts are summed as posted |
| Where it is maintained | Consolidation Group (Desk has a tree view) | Reporting Hierarchy and Reporting Hierarchy Member |

If DE01 sells 50 to AT01 inside the group, a consolidation of DE01 and AT01 removes the 50. A `DACH` node over their business units keeps it. See the [Consolidation Guide](consolidation-guide.md) for legal-entity roll-ups.

## Worked Example

Revenue postings on account `400000` for fiscal 2026, each carrying a business unit (illustrative figures):

| Legal entity | Business unit on the posting | Revenue |
|---|---|---|
| DE01 (German company) | BU_DE01 | 500 |
| DE01 (German company) | BU_AT01 | 100 |
| AT01 (Austrian company) | BU_AT01 | 300 |
| CH01 (Swiss company) | BU_CH01 | 200 |
| FR01 (French company) | BU_FR01 | 150 |
| US01 (US company) | BU_US01 | 1,000 |

The second row matters: the German company booked a sale for the Austrian business unit, so the Austrian business unit is not the same as the Austrian company's books.

The tree `MGMT_2026` on `dim_business_unit`:

```
TOTAL                (group)
├── EUROPE           (group)
│   ├── DACH         (group)
│   │   ├── BU_DE01  (leaf)
│   │   ├── BU_AT01  (leaf)
│   │   └── BU_CH01  (leaf)
│   └── BU_FR01      (leaf)
└── BU_US01          (leaf)
```

Node totals the warehouse precomputes:

| Node | Made of | Revenue |
|---|---|---|
| BU_AT01 | 300 from AT01 + 100 from DE01 | 400 |
| DACH | BU_DE01 + BU_AT01 + BU_CH01 | 1,100 |
| EUROPE | DACH + BU_FR01 | 1,250 |
| TOTAL | EUROPE + BU_US01 | 2,250 |

## Building and Publishing a Tree

Publishing and unpublishing trees, and editing saved trees and members, needs the **EPM Admin** (Close Lead) or **System Manager** role. A Group Accountant (EPM Analyst) can create a new tree or member but cannot change it once saved. Viewers can read trees in Desk.

1. **Publish the dimension.** The tree's dimension must be Published (Lists → EPM → Dimension).
2. **Create the tree.** Lists → EPM → **Reporting Hierarchy** → New:

    | Field | Example | Notes |
    |---|---|---|
    | Hierarchy Name | `MGMT_2026` | The name formulas use. Must be unique |
    | Dimension | `dim_business_unit` | The one dimension the tree rolls up |
    | Label | Management structure 2026 | Display name |
    | Effective From / Effective To | 2026-01-01 / 9999-12-31 | Recorded only; see [Not Yet Available](#not-yet-available) |
    | Default Hierarchy | checked | At most one per dimension (among trees that are not Inactive) |
    | Status | Draft | Leave it to **Actions → Publish** and **Unpublish**: the field can be edited, but setting it by hand skips the publish checks and requests no build |

3. **Add the members.** Lists → EPM → **Reporting Hierarchy Member** → New, one record per node:

    | Field | Group node | Leaf node |
    |---|---|---|
    | Reporting Hierarchy | `MGMT_2026` | `MGMT_2026` |
    | Parent Member | blank for the top node, else its parent | the group it sits under |
    | Member Code | optional: left blank, it is made from the label ("Other regions" becomes `OTHER_REGIONS`) | **required**: the exact dimension code, e.g. `BU_AT01` |
    | Member Label | `DACH` | `Austria` |
    | Is Group | checked | unchecked |

    Members are listed with a Parent Member link, not drawn as a tree.

4. **Publish.** Open the tree and choose **Actions → Publish**. Publishing sends the tree to the warehouse and requests a build of the reporting models (a [Build Approval](../reference/glossary.md#konsol-close-and-reporting-terms) with scope `reporting`). The node totals can be read once that build has finished.

To change a published tree, choose **Actions → Unpublish** (the status becomes Inactive), edit the members, and **Publish** again. A Published tree cannot be deleted; unpublish it first.

### Rules Checked When You Save or Publish

| Rule | Message |
|---|---|
| Member codes are unique within a tree, for groups as well as leaves | "Member code 'DACH' already exists in this hierarchy (…). Formulas and the warehouse find a node by its code, so set a different Member Code." |
| A leaf needs a code | "Member Code is required for leaf nodes (Is Group = unchecked)." |
| A parent belongs to the same tree | "Parent member must belong to the same Reporting Hierarchy." |
| No loops | "Parent chain forms a cycle — choose a different parent." |
| One default per dimension | "Dimension 'dim_business_unit' already has a default hierarchy (MGMT_2025). Clear is_default on the other hierarchy first." |
| The dimension is published (checked at Publish, and on saving a Published tree) | "Dimension 'dim_business_unit' must be Published before saving a Reporting Hierarchy. Publish the dimension first." |
| A tree has members (checked at Publish only) | "Add at least one Reporting Hierarchy Member before publishing." |
| A published tree is not deleted | "Unpublish this Reporting Hierarchy before deleting it." |
| Only the Close Lead or a System Manager publishes | "You need the 'EPM Admin' role to publish or unpublish." |

Unique codes matter because the warehouse and `K.EPM` find a node by its code: two members sharing one code would be merged into one node.

## Reading a Node from Excel

`K.EPM` takes the tree and the node as its 10th and 11th arguments, hence the run of empty arguments:

```
=K.EPM(entity, fiscal_year, fiscal_period, account, [measure], [scenario], [cost_center], [department], [scenario_id], [hierarchy], [node], [layer])
```

Setting `node` switches the read from one entity's figures to the node totals. Without `node`, the formula is a plain entity read and `hierarchy` is ignored.

The worked example in Excel:

| Formula | Result | Reads |
|---|---|---|
| `=K.EPM("AT01", 2026, "FY", "400000")` | 300 | The Austrian company's books, every business unit |
| `=K.EPM("ALL", 2026, "FY", "400000", , , , , , "MGMT_2026", "BU_AT01")` | 400 | The Austrian business unit, every company |
| `=K.EPM("ALL", 2026, "FY", "400000", , , , , , "MGMT_2026", "DACH")` | 1,100 | DACH, every company |
| `=K.EPM("DE01", 2026, "FY", "400000", , , , , , "MGMT_2026", "DACH")` | 600 | The German company's share of DACH (500 + 100) |
| `=K.EPM("ALL", 2026, "FY", "400000", , , , , , "MGMT_2026", "EUROPE")` | 1,250 | EUROPE, every company |

`entity` and `node` are two independent filters: `entity` picks whose books, `node` picks which branch of the tree.

### The Entity Argument

- `"ALL"`, `"*"` or a blank entity means every entity **you are allowed to see**.
- If your access is limited to some entities, node totals include only those. A user limited to DE01 and AT01 gets **900** for DACH in the example (500 + 100 + 300), not 1,100.
- A named entity you may not see gives `#VALUE!` "Not permitted to access entity 'CH01'". A user with no entities at all gets "Not permitted to access any entity" for an `"ALL"` read.
- Outside hierarchy mode (no `node`), a blank entity is not a wildcard: a user limited to some entities who leaves it blank is refused.

### Scenarios, Measures and Layers at a Node

| Scenario | Measures | Notes |
|---|---|---|
| `actuals` (default) | `period_net_amount` (default), `period_debit`, `period_credit`, `transaction_count` | `ytd_net_amount` is not available at a node |
| `budget`, `forecast` | `period_amount` (default), `annual_amount` | `scenario_id` picks a version; `layer` picks one budget layer, and blank sums all layers |
| `variance` | `variance_abs` (default), `actual_amount`, `budget_amount` | |

Budget, forecast and variance need the tree's dimension to be a budget dimension (**Include in Budget** on the Dimension). Otherwise the cell shows `#VALUE!` "Hierarchy axis 'dim_business_unit' is not supported for scenario 'budget' (requires in_budget dimensions: …). Use actuals for this hierarchy, or rebuild the hierarchy on a budget dimension."

The shorthand functions take the same two arguments:

```
=K.EPM_BUDGET("ALL", 2026, "FY", "400000", "", "", "BUDGET_2026", "MGMT_2026", "DACH")
=K.EPM_VARIANCE("ALL", 2026, "FY", "400000", "", "", "", "MGMT_2026", "DACH")
=K.EPM_DEBIT("DE01", 2026, 9, "400000", "", "", "MGMT_2026", "BU_AT01")
```

`K.EPMSAVE` writes at a **leaf** only: it saves the budget cell with the leaf's code on the tree's dimension. A group node is refused ("Node 'DACH' is a group — budget write-back is only allowed at leaf nodes."). See the [Excel Formulas Guide](excel-formulas-guide.md#kepmsave-budget-write-back).

### How the Tree Is Chosen

| What the formula gives | Result |
|---|---|
| `hierarchy` names a Published tree | That tree. The name is matched without regard to case (`mgmt_2026` reads `MGMT_2026`) |
| `hierarchy` names a tree that is missing or not Published | `#VALUE!` "Reporting Hierarchy 'MGMT_2026' not found or not published" |
| `hierarchy` is named, but the node is not in it | `#VALUE!` "Node 'DACH' not found in hierarchy 'MGMT_2026'" |
| `hierarchy` blank, the node is in exactly one Published tree | That tree |
| `hierarchy` blank, the node is in several Published trees | `#VALUE!` "Node 'DACH' is in 2 published hierarchies (MGMT_2026, MGMT_2027). Pass the hierarchy name to choose one." |
| `hierarchy` blank, the node is in no Published tree | `#VALUE!` "Node 'DACH' is not in any published Reporting Hierarchy." |
| Two members of one tree share the code (older data, saved before codes had to be unique) | `#VALUE!` "Node 'DACH' is used by 2 members of hierarchy 'MGMT_2026' (DACH, DACH region). Give each member its own Member Code." |

Neither the default tree nor the fiscal year picks a tree. Resolution is strict so that a formula never changes its answer because someone edited a different tree. Suppose `MGMT_2026` has DACH = DE + AT + CH (1,100) and `MGMT_2027` moves Switzerland out (DACH = DE + AT, 900): a formula without a hierarchy name is an error, not 900 one day and 1,100 the next. **Name the hierarchy in every report you keep.**

## Not Yet Available

- **No hierarchy screen.** konsol-exec has no view of reporting hierarchies. In Desk, members are a flat list with a Parent Member link, and the Reporting Hierarchy form only adds Publish and Unpublish. The node totals and the list of unassigned codes are in the warehouse but are not shown in konsol. (Consolidation Group, the legal-entity tree, does have a tree view in Desk.)
- **Effective dates are recorded, not applied.** Effective From and Effective To do not choose a tree or limit a node's figures. Use separate trees (for example `MGMT_2026` and `MGMT_2027`) and name the one you want.
- **Named arguments.** Formulas take positional arguments only. A named-parameter form of `K.EPM` is on the roadmap.

## Next Steps

- [Excel Formulas Guide](excel-formulas-guide.md): every `K.` function and its arguments
- [Consolidation Guide](consolidation-guide.md): legal-entity roll-ups with eliminations
- [Budget Layers Guide](budget-layers.md): the layers that `layer` selects
