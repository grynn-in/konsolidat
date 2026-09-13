# Glossary

## Finance & EPM/CPM Terms

| Term | Definition |
|------|-----------|
| **Consolidation** | Combining financial statements of multiple legal entities into a single group report, including FX translation and intercompany elimination |
| **CTA (Currency Translation Adjustment)** | The difference arising when P&L is translated at average rate but the balance sheet at closing rate; posted as an equity adjustment |
| **Closing Rate** | The exchange rate on the last day of the reporting period; used for balance sheet translation |
| **Average Rate** | The mean exchange rate over the reporting period; used for P&L translation |
| **Historical Rate** | The exchange rate at the date of the original transaction; used for equity accounts |
| **NCI (Non-Controlling Interest)** | The portion of a subsidiary's equity not owned by the parent; calculated as `translated_amount × (1 − ownership_pct)` |
| **Group Amount** | The parent's share of a subsidiary's translated balance: `translated_amount × ownership_pct` |
| **Intercompany (IC) Elimination** | Removing transactions between entities within the same consolidation group so they don't double-count |
| **Topside Journal / Consolidation Adjustment** | Manual journal entries posted at the group level (e.g., goodwill, fair-value adjustments) |
| **Trial Balance** | A listing of all accounts and their balances for a given period, where total debits must equal total credits |
| **Fully Consolidated Trial Balance (FCTB)** | The final 4-layer union: entity amounts + IC eliminations + CTA + topside adjustments |
| **Chart of Accounts** | The master list of all general ledger account codes and their types (Revenue, Expense, Asset, Liability, Equity) |
| **Cost Center** | An organizational unit used to track where costs are incurred (e.g., IT, Sales, Facility) |
| **Driver-Based Allocation** | Distributing a cost pool across recipients based on a measurable driver (headcount, square meters, revenue) |
| **Spread Profile** | A set of 12 monthly weights that determine how an annual budget amount is distributed across fiscal periods |
| **Variance** | The difference between actual and budget amounts; can be expressed as absolute, percentage, or favorable/unfavorable |
| **Favorable Variance** | Revenue: actual > budget. Expense: actual < budget. |
| **YTD (Year-to-Date)** | Cumulative total from period 1 through the current period |
| **Fiscal Period** | A numbered month (1–12) within a fiscal year, plus optional special periods (0 = Opening, 13 = Closing) |
| **Scenario** | A named version of financial data: `actuals`, `budget`, or `forecast` |

## Konsol Close and Reporting Terms

| Term | Definition |
|------|-----------|
| **Reporting Hierarchy** | A management tree over one dimension (for example business unit), built in konsol and read from Excel with `K.EPM`. It adds up across entities with no eliminations. See [Reporting Hierarchies](../user-guide/reporting-hierarchies-guide.md) |
| **Node** | Any member of a Reporting Hierarchy, found by its Member Code. A node's value is the sum of every leaf below it |
| **Leaf** | A member with **Is Group** unchecked, whose Member Code is a real dimension code on the postings, such as `BU_AT01`. Group nodes are headings that only add up leaves |
| **Group Exchange Rate** | The approved Closing or Average rate for one currency into a group reporting currency for one fiscal period. konsol publishes the true rate (units of group currency per 1 entity-currency unit), and translation reads only these rates |
| **Quoted Per** | How many units of the from-currency a Group Exchange Rate quote is for: 1, 10, 100, 1,000 or 10,000. A quote of 0.6607 USD per 100 JPY is published as the true rate 0.006607 |
| **USD reference** | A rough size for each currency (about log10 of its units per 1 USD), kept on ISO Currency. A rate more than 10 times away from what the references imply is refused as a likely typing error |
| **Governed rate** | A rate approved by group finance in konsol (a submitted Group Exchange Rate). The ERP feed only proposes draft rates, and a period cannot close while a translated currency lacks one |
| **Intercompany Account** | A group chart account flagged as intercompany (Published), with the counterpart account the partner books the other side on. Its trial balance rows need a partner entity to be eliminated |
| **Partner entity** | The other group entity an intercompany row is held with (`partner_data_area_id` on a trial balance row). A row without one loads but is never eliminated, and is listed as unmatched |
| **Booking difference** | A pair difference where both sides are in one functional currency and their local amounts don't net to zero: a different amount was booked, or one side hasn't booked yet. Only booking differences count against the group's Intercompany Difference Tolerance |
| **FX difference** | A pair difference that arises because the sides are in different currencies, or from translation alone. It is shown but never counts against the tolerance |
| **NCI line** | The account (by default the pseudo-account `NCI`) where the minority owners' share of intercompany eliminations is posted. The group view carries a balance on it; added to the NCI view, it nets to zero per group and period |
| **Elimination view** | Which share an intercompany elimination entry covers: `group` (the group's share, booked in the consolidated trial balance) or `nci` (the minority owners' share). Group plus NCI is the full (100%) consolidation |
| **Build Approval** | A governed request to rebuild the warehouse for a scope (for example `consolidation`, `reporting` or `full`). Every scope except `staging` waits in Pending Review for the Close Lead; a Running build can only be moved on by the build itself |
| **Trial Balance Upload** | The audit record of one bulk trial balance file: its checks, and the Trial Balance Submission it created for each entity and period. See [Trial Balance Upload](../user-guide/trial-balance-upload-guide.md) |
| **Close Lead** | The job title konsol shows for the EPM Admin role: runs the close, approves builds and adjustments, signs off periods |
| **Entity Accountant** | A role for people who submit trial balances (one entity and period at a time, through Trial Balance Submission) and the base budget, for their assigned entities only. One with no entity assigned sees no entity |
| **Month stages** | The eight ordered steps of a month's close in konsol-exec: source data, trial balances, ownership & rates, intercompany, adjustments, consolidate, assertions, sign off. See [Month-End Close](../user-guide/month-close-guide.md) |

## Technical Terms

| Term | Definition |
|------|-----------|
| **Medallion Architecture** | A data layering pattern: Bronze (raw) → Silver (cleaned) → Gold (business logic) |
| **Bronze Layer** | Raw data from source systems, type-cast and snake_cased but otherwise unmodified. Schema: `epm_bronze` |
| **Silver Layer** | Deduplicated, standardized, joined data ready for business logic. Schema: `epm_silver` |
| **Gold Layer** | Business-ready models consumed by reports and APIs. Schema: `epm_gold` |
| **Staging Layer** | Intermediate views for field renames and joins. Schema: `epm_staging` |
| **dbt (data build tool)** | An open-source SQL transformation framework that compiles Jinja-SQL into executable queries |
| **Seed** | A CSV file managed by dbt, loaded into the warehouse as a table (used for reference data like allocation rules) |
| **Macro** | A reusable Jinja template in dbt that generates SQL fragments |
| **Materialization** | How dbt persists a model: `table` (full rebuild), `view` (virtual), or `incremental` (append/merge) |
| **ClickHouse** | A columnar OLAP database optimized for analytical queries; used as the data warehouse |
| **MergeTree** | ClickHouse's primary table engine; supports sorting keys for fast range queries |
| **Frappe** | A Python web framework with built-in auth, roles, DocTypes, and REST API; hosts the Konsol app |
| **DocType** | A Frappe data model definition (schema + UI + permissions + workflow) |
| **Konsol** | The Frappe app that provides EPM Settings, pipeline control, and the `=K.EPM()` API |
| **EPM Settings** | A Frappe Single DocType storing ClickHouse connection details, Airbyte config, and dbt project path |
| **Airbyte** | An open-source ELT platform; extracts D365 OData entities into ClickHouse |
| **abctl** | Airbyte's CLI tool for self-hosted deployment |
| **OData** | A REST protocol used by D365 F&O to expose data entities |
| **Excel add-in** | The konsol Office add-in: the `=K.EPM()` worksheet functions and the Konsolidat task pane |
| **Office.js** | Microsoft's JavaScript API for building Office Add-ins (task panes, custom functions) |

## Abbreviations

| Abbrev. | Expansion |
|---------|-----------|
| BS | Balance Sheet |
| P&L | Profit and Loss (Income Statement) |
| CF | Cash Flow |
| FX | Foreign Exchange |
| IC | Intercompany |
| TB | Trial Balance |
| GL | General Ledger |
| FCTB | Fully Consolidated Trial Balance |
| EPM/CPM | Corporate Performance Management |
| EPM | Enterprise Performance Management |
| ELT | Extract, Load, Transform |
| OLAP | Online Analytical Processing |
| RBAC | Role-Based Access Control |
| SSO | Single Sign-On |
| TCO | Total Cost of Ownership |
