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
| **Konsol** | The Frappe app that provides EPM Settings, pipeline control, and the `=EPM()` API |
| **EPM Settings** | A Frappe Single DocType storing ClickHouse connection details, Airbyte config, and dbt project path |
| **Airbyte** | An open-source ELT platform; extracts D365 OData entities into ClickHouse |
| **abctl** | Airbyte's CLI tool for self-hosted deployment |
| **OData** | A REST protocol used by D365 F&O to expose data entities |
| **VBA (Visual Basic for Applications)** | The macro language in Excel used to implement the `=EPM()` custom functions |
| **Office.js** | Microsoft's JavaScript API for building Office Add-ins (task panes, custom functions) |
| **Custom Document Property** | An Excel workbook-level metadata field; used to store `EPM_API_URL` |

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
