"""The onboarding workbook: one sheet per konsol doctype, columns = fieldnames.

Shared by build_workbooks.py (which writes the blank template and the Aquila
example) and konsol_load.py (which reads a filled workbook and writes it to a
konsol site through frappectl). Both read SHEETS here, so the two cannot drift.

Every sheet's header row is the doctype's fieldnames, so a sheet is also
importable one at a time through Frappe's Data Import tool. A few columns are
loader-only (marked loader=True): they name a parent by its code because the
Frappe name of the parent (a hash, or CG-{group}-{entity}) is not something a
person filling in a workbook should have to know.
"""
from __future__ import annotations

from dataclasses import dataclass, field

TB_HEADER = ("data_area_id", "fiscal_year", "fiscal_period", "main_account", "debit", "credit",
             "currency", "description", "partner_data_area_id", "amount_basis")

AMOUNT_BASES = ("Period movement", "Year-to-date movement", "Period-end balance")


@dataclass(frozen=True)
class Col:
    name: str
    help: str
    required: bool = False
    kind: str = "text"       # text | int | float | date | check | select
    options: tuple = ()
    loader: bool = False     # resolved by konsol_load.py, not a doctype field
    width: int = 18


@dataclass(frozen=True)
class Sheet:
    name: str
    doctype: str
    purpose: str
    cols: tuple
    key: tuple                 # natural key: which columns identify a row on the site
    submit: bool = False       # submittable doctype: create, then submit
    workflow: bool = False     # konsol installs a Frappe Workflow on it (konsol/workflows.py INSTALLED): approval is
                               # Send for Approval + approve, not a plain submit
    tree: str = ""             # column that names the parent row (parents load first)
    parent_sheet: str = ""     # child-table sheet: the Sheet whose rows it nests into (never loaded on its own)
    table_field: str = ""      # child-table sheet: the parent doctype's Table fieldname its rows become
    notes: tuple = field(default_factory=tuple)

    @property
    def fieldnames(self):
        return [c.name for c in self.cols]

    def col(self, name):
        return next(c for c in self.cols if c.name == name)


STATUS = ("Draft", "Published", "Inactive")
#: konsol.close.close_policy_model.APPROVAL_DOCTYPES: submit = approval, judged by the self-approval policy, so the
#: loader approves these through konsol.close.approval_api.approve (with a reason), never a bare submit.
APPROVAL_DOCTYPES = ("Consolidation Journal", "Business Combination", "Business Disposal", "Group Exchange Rate",
                     "Ownership Period", "Historical Equity Rate", "IC Balance")
CLOSE_SETTINGS_KEYS = ("self_approval",)

SHEETS: tuple[Sheet, ...] = (
    Sheet(
        "Settings", "EPM Settings",
        "Site-wide switches the trial-balance intake reads. One row per setting.",
        (
            Col("setting", "EPM Settings fieldname, or self_approval (Close Settings).", True, "select",
                ("default_amount_basis", "tb_accepts_opening", "tb_accepts_closing", "tb_accepts_adjustment", "self_approval"), width=28),
            Col("value", "The value. Amount basis is one of the three exact strings; the tb_accepts_* flags are 1 or 0; "
                "self_approval is Blocked or Allowed with reason.", True, width=28),
        ),
        key=("setting",),
        notes=("self_approval (Close Settings): whether the person who prepared a document may approve it. An onboarding load "
               "is prepared and approved by the same person, so declare Allowed with reason, or leave it and have a second "
               "Close Lead approve every submitted row afterwards (undeclared, every approval is refused by name).",
               "default_amount_basis pre-fills the bulk upload page; it is never applied silently.",
               "tb_accepts_opening / tb_accepts_closing / tb_accepts_adjustment: whether a trial balance may be posted to those period types. Leave 0 unless you post to them."),
    ),
    Sheet(
        "Fiscal_Years", "EPM Fiscal Year",
        "One row per fiscal year you will load. The periods come from the Fiscal_Periods sheet.",
        (
            Col("fiscal_year", "Four-digit fiscal year, e.g. 2026. Also the document name.", True, "int", width=12),
            Col("start_date", "First day of the fiscal year (ISO date).", True, "date", width=12),
            Col("end_date", "Last day of the fiscal year (ISO date).", True, "date", width=12),
            Col("period_pattern", "Monthly (12), 13 Periods (4 Weeks), 4-4-5 or Custom.", True, "select",
                ("Monthly (12)", "13 Periods (4 Weeks)", "4-4-5", "Custom"), width=20),
            Col("include_opening_period", "1 = an OPN row (period 0) exists for opening balances.", False, "check", width=12),
            Col("include_closing_period", "1 = a CLS row (period 13) exists. Required for Period-end balance files: the year-end close is posted there.", False, "check", width=12),
        ),
        key=("fiscal_year",),
        notes=("Load the year before the year-end balances you start from (2025) as well as the year you upload monthly (2026).",
               "A Period-end balance history needs a Closing period AND exactly one Published account flagged is_retained_earnings."),
    ),
    Sheet(
        "Fiscal_Periods", "EPM Fiscal Year Period",
        "The period rows of each fiscal year (child table `periods` of EPM Fiscal Year).",
        (
            Col("fiscal_year", "The Fiscal_Years row this period belongs to.", True, "int", width=12),
            Col("fiscal_period", "Period number: 0 = Opening, 1..12 = Regular, 13 = Closing (Monthly pattern).", True, "int", width=12),
            Col("period_code", "Short code: OPN, P01..P12, CLS.", True, width=12),
            Col("period_label", "Label shown in reports, e.g. Jan 2026.", False, width=16),
            Col("period_type", "Opening, Regular, Closing or Adjustment.", True, "select", ("Opening", "Regular", "Closing", "Adjustment"), width=12),
            Col("quarter", "Q1..Q4 for Regular periods; blank for OPN/CLS.", False, "select", ("", "Q1", "Q2", "Q3", "Q4"), width=10),
            Col("start_date", "First day of the period (ISO date).", True, "date", width=12),
            Col("end_date", "Last day of the period (ISO date).", True, "date", width=12),
        ),
        key=("fiscal_year", "fiscal_period"),
    ),
    Sheet(
        "Entities", "Entity",
        "Every legal entity and every management roll-up node. The entity code is the data_area_id used everywhere else.",
        (
            Col("entity_code", "Unique code, upper case, no spaces. This is the data_area_id on trial balances.", True, width=14),
            Col("entity_name", "Legal or roll-up name.", True, width=40),
            Col("parent_entity", "entity_code of the management parent (a row with is_group = 1). Blank for the top node.", False, width=14),
            Col("is_group", "1 for a roll-up node (regions, divisions); 0 for a legal entity that submits a trial balance.", False, "check", width=10),
            Col("status", "Active, Dormant or Disposed.", False, "select", ("Active", "Dormant", "Disposed"), width=10),
            Col("reporting_frequency", "Monthly or Quarterly.", False, "select", ("", "Monthly", "Quarterly"), width=12),
            Col("functional_currency", "ISO 4217 code the entity keeps its books in. Required for every legal entity: trial balances must carry exactly this currency.", False, width=10),
            Col("country", "ISO 3166-1 alpha-2 country code.", False, width=8),
            Col("erp_source", "Where the ledger comes from: tb_upload, d365_fo, sap_s4, erpnext ... Free text.", False, width=12),
        ),
        key=("entity_code",), tree="parent_entity",
        notes=("This is the MANAGEMENT tree (regions). Legal ownership lives in Consolidation_Groups and Ownership_Periods.",
               "Only a row with is_group = 1 may have children."),
    ),
    Sheet(
        "Dimensions", "Dimension",
        "The analysis dimensions (cost centre, business line, ...). A dimension ticked in_trial_balance becomes a dim_<name> column on trial-balance files.",
        (
            Col("dimension_name", "dim_ followed by lower-case letters, digits and underscores, e.g. dim_cost_center. This exact string is the trial-balance column header.", True, width=22),
            Col("source_column", "The column in your ERP extract that carries this dimension (connector-fed sites). On an upload-only site repeat the dimension name (e.g. dim_cost_center): the warehouse reads this column from its staging views.", True, width=18),
            Col("label", "Display label.", True, width=18),
            Col("cube_type", "string or number.", False, "select", ("string", "number"), width=10),
            Col("in_budget", "1 = appears on budget sheets.", False, "check", width=9),
            Col("in_trial_balance", "1 = trial-balance files may carry a dim_<name> column for it.", False, "check", width=9),
            Col("in_journal", "1 = consolidation journals may carry it.", False, "check", width=9),
            Col("survives_close", "Leave 0: the year-end close carries no dimension values yet (konsol#255).", False, "check", width=9),
            Col("status", "Published to make it live.", False, "select", STATUS, width=10),
        ),
        key=("dimension_name",),
    ),
    Sheet(
        "Reporting_Hierarchies", "Reporting Hierarchy",
        "Management reporting trees on a dimension (divisions, regions, cost-centre groups). Members are on the next sheet.",
        (
            Col("hierarchy_name", "Unique name, e.g. DIVISIONS.", True, width=20),
            Col("dimension", "dimension_name this tree rolls up (must be Published).", True, width=20),
            Col("label", "Display label.", True, width=24),
            Col("effective_from", "First day the hierarchy applies (ISO date).", False, "date", width=12),
            Col("effective_to", "Last day it applies; 9999-12-31 = open.", False, "date", width=12),
            Col("is_default", "1 = the default tree for this dimension (one per dimension).", False, "check", width=9),
            Col("status", "Published once it has members.", False, "select", STATUS, width=10),
        ),
        key=("hierarchy_name",),
    ),
    Sheet(
        "Reporting_Hierarchy_Members", "Reporting Hierarchy Member",
        "The nodes of each hierarchy. Leaf member_codes are the dimension values that appear on trial balances.",
        (
            Col("reporting_hierarchy", "hierarchy_name of the tree.", True, width=20),
            Col("member_code", "Node code. For a leaf: the exact dimension value used on trial balances.", True, width=16),
            Col("member_label", "Display label.", True, width=28),
            Col("parent_member_code", "member_code of the parent node (same hierarchy). Blank for the root.", False, width=16, loader=True),
            Col("is_group", "1 for a roll-up node, 0 for a leaf.", False, "check", width=9),
            Col("effective_from", "First day this node (tranche) applies.", True, "date", width=12),
            Col("effective_to", "Last day; blank = open.", False, "date", width=12),
        ),
        key=("reporting_hierarchy", "member_code", "effective_from"), tree="parent_member_code",
    ),
    Sheet(
        "Dimension_Mappings", "Dimension Mapping",
        "OPTIONAL, connector-fed entities only: maps a raw ERP dimension value to the canonical value used in reporting. Upload-only sites leave this empty.",
        (
            Col("dimension", "dimension_name.", True, width=20),
            Col("erp_source", "d365_fo, d365_bc, sap_s4, sap_ecc, sap_b1 or erpnext.", True, "select",
                ("d365_fo", "d365_bc", "sap_s4", "sap_ecc", "sap_b1", "erpnext"), width=10),
            Col("entity", "entity_code the mapping is specific to; blank = ERP-wide default.", False, width=12),
            Col("source_value", "The value as the ERP exports it.", True, width=16),
            Col("canonical_value", "The value reporting uses (a hierarchy leaf code).", True, width=16),
            Col("canonical_label", "Label.", False, width=24),
            Col("status", "Published to apply.", False, "select", STATUS, width=10),
        ),
        key=("dimension", "erp_source", "entity", "source_value"),
    ),
    Sheet(
        "Main_Accounts", "Main Account",
        "The group chart of accounts: headings (is_group = 1) and posting accounts. A trial balance may only post to Published, non-heading, is_posting accounts.",
        (
            Col("main_account", "Account code. The join key in the warehouse; keep it stable.", True, width=12),
            Col("account_name", "Name.", True, width=42),
            Col("chart_of_accounts", "Chart code, the same on every row, e.g. GROUP.", True, width=14),
            Col("parent_account", "main_account of the heading above (is_group = 1, same chart, same statement). Blank for a top heading.", False, width=12),
            Col("is_group", "1 = heading (never posted to), 0 = posting account.", False, "check", width=9),
            Col("account_type", "Asset, Liability, Equity, Revenue, Expense (or the generic Balance sheet / Profit and loss).", False, "select",
                ("", "Asset", "Liability", "Equity", "Revenue", "Expense", "Balance sheet", "Profit and loss"), width=12),
            Col("statement_section", "Balance Sheet or Profit and Loss.", False, "select", ("", "Balance Sheet", "Profit and Loss"), width=16),
            Col("sub_section", "Free text used to group the statement, e.g. Non-current assets.", False, width=24),
            Col("normal_balance", "Debit or Credit. A contra account (accumulated depreciation) carries the opposite side.", False, "select", ("", "Debit", "Credit"), width=10),
            Col("time_balance", "balance for Balance Sheet accounts, flow for Profit and Loss.", False, "select", ("", "balance", "flow"), width=10),
            Col("fx_method", "closing (balance sheet), average (P&L) or historical (equity only, IAS 21).", False, "select", ("", "closing", "average", "historical"), width=10),
            Col("is_posting", "1 = open for posting. 0 on headings.", False, "check", width=9),
            Col("allow_ic", "1 = rows on this account may carry a partner entity (intercompany). Pair it on Intercompany_Accounts.", False, "check", width=9),
            Col("is_cash", "1 = cash or cash equivalent (drives the cash-flow statement).", False, "check", width=9),
            Col("is_retained_earnings", "1 on exactly ONE posting Equity account per chart: the year-end close posts the result there.", False, "check", width=9),
            Col("cf_category", "Operating, Investing or Financing. Required on every Balance Sheet posting account that is not cash.", False, "select",
                ("", "Operating", "Investing", "Financing"), width=12),
            Col("cf_line_item", "Cash-flow statement line the movement is shown on.", False, width=30),
            Col("main_account_category", "Optional budget category.", False, width=16),
            Col("status", "Published puts the account in the group chart.", False, "select", STATUS, width=10),
            Col("description", "Optional.", False, width=30),
        ),
        key=("main_account",), tree="parent_account",
        notes=("Headings load before the accounts under them; a heading must be Published before its children can be.",
               "Changing account_type, statement_section or fx_method on a Published account re-translates every period: decide them once."),
    ),
    Sheet(
        "Intercompany_Accounts", "Intercompany Account",
        "Which posting accounts are intercompany, and the account the PARTNER books the other side on. Each account belongs to exactly one pair.",
        (
            Col("main_account", "An account with allow_ic = 1.", True, width=12),
            Col("counterpart_account", "The account the partner uses for the other side (receivable -> payable, revenue -> cost). Blank = both sides use main_account.", False, width=14),
            Col("status", "Published to eliminate.", False, "select", STATUS, width=10),
            Col("description", "Optional.", False, width=40),
        ),
        key=("main_account",),
    ),
    Sheet(
        "IC_Elimination_Rules", "IC Elimination Rule",
        "OPTIONAL special cases only (unrealised profit in inventory). Ordinary receivable/payable and revenue/cost eliminations come from Intercompany_Accounts.",
        (
            Col("rule_id", "Unique id.", True, width=14),
            Col("rule_name", "Name.", True, width=30),
            Col("rule_type", "balance or unrealized_profit.", True, "select", ("balance", "unrealized_profit"), width=14),
            Col("debit_account", "Account debited by the elimination.", True, width=12),
            Col("credit_account", "Account credited by the elimination.", True, width=12),
            Col("debit_entity_pattern", "Entity pattern on the debit side; * = any.", False, width=12),
            Col("credit_entity_pattern", "Entity pattern on the credit side; * = any.", False, width=12),
            Col("margin_pct", "unrealized_profit only: intercompany gross margin %, e.g. 25.", False, "float", width=10),
            Col("asset_account", "unrealized_profit only: the inventory account carrying the unrealised margin.", False, width=12),
            Col("description", "Optional.", False, width=40),
        ),
        key=("rule_id",),
    ),
    Sheet(
        "Scenarios", "Scenario",
        "Scenarios data is tagged with. konsol ships defaults; rows here are created only when missing.",
        (
            Col("scenario_id", "Unique id, e.g. ACTUAL.", True, width=14),
            Col("scenario_name", "Name.", True, width=24),
            Col("scenario_type", "actual, budget, forecast, strategic or operational.", True, "select",
                ("actual", "budget", "forecast", "strategic", "operational"), width=12),
            Col("is_active", "1 = active.", False, "check", width=9),
        ),
        key=("scenario_id",),
    ),
    Sheet(
        "Consolidation_Groups", "Consolidation Group",
        "The LEGAL consolidation tree: group nodes (no entity) and the entity nodes under them. Policy fields are filled on the root group node only.",
        (
            Col("consolidation_group", "Group code. On a group node: its own code. On an entity node: the code of the group it sits in.", True, width=14),
            Col("data_area_id", "entity_code for an entity node; BLANK for a group node.", False, width=12),
            Col("entity_name", "Name of the node.", True, width=40),
            Col("parent_group", "consolidation_group code of the parent GROUP node. Blank only for the root.", False, width=14, loader=True),
            Col("is_group", "1 for a group node, 0 for an entity node.", False, "check", width=9),
            Col("reporting_currency", "Group nodes: the currency this (sub)group presents in. Every entity below is translated into it.", False, width=10),
            Col("accounting_framework", "Root only: IFRS, US GAAP or Local.", False, "select", ("", "IFRS", "US GAAP", "Local"), width=10),
            Col("goodwill_method", "Root only: NCI measurement, partial or full.", False, "select", ("", "partial", "full"), width=10),
            Col("goodwill_treatment", "Root only: Impairment only or Amortise.", False, "select", ("", "Impairment only", "Amortise"), width=14),
            Col("goodwill_amortisation_years", "Root only, when Amortise.", False, "int", width=10),
            Col("acquisition_costs_treatment", "Root only: Expense or Capitalise.", False, "select", ("", "Expense", "Capitalise"), width=12),
            Col("measurement_period", "Root only: Off or 12 months.", False, "select", ("", "Off", "12 months"), width=10),
            Col("bargain_purchase", "Root only: Recognise gain or Refuse.", False, "select", ("", "Recognise gain", "Refuse"), width=14),
            Col("ic_difference_account", "Group nodes: P&L account that takes the difference when an intercompany pair does not match (a Published posting account, not itself intercompany).", False, width=12),
            Col("ic_difference_tolerance", "Group nodes: difference shown as tolerated, in reporting currency.", False, "float", width=10),
            Col("goodwill_account", "Root only: the accounts consolidation journals post to (all Published posting accounts).", False, width=10),
            Col("fair_value_adjustment_account", "Root only.", False, width=10),
            Col("investment_account", "Root only.", False, width=10),
            Col("nci_account", "Root only.", False, width=10),
            Col("bargain_purchase_gain_account", "Root only.", False, width=10),
            Col("disposal_gain_loss_account", "Root only.", False, width=10),
            Col("disposal_proceeds_account", "Root only.", False, width=10),
            Col("goodwill_amortisation_expense_account", "Root only.", False, width=10),
            Col("acquisition_costs_account", "Root only.", False, width=10),
        ),
        key=("consolidation_group", "data_area_id"), tree="parent_group",
        notes=("An entity belongs to exactly one node. Ownership percentages are NOT here: they are dated, on Ownership_Periods.",
               "Translation needs an approved Closing and Average rate from every entity currency into each group node's reporting currency, per period (FX_Rates)."),
    ),
    Sheet(
        "Ownership_Periods", "Ownership Period",
        "How much of each non-root node its parent owns, from effective_date until end_date. Submitted on load.",
        (
            Col("consolidation_group", "The node's group code (as on Consolidation_Groups).", True, width=14),
            Col("data_area_id", "entity_code of an entity node; BLANK for a sub-group node.", False, width=12),
            Col("effective_date", "First day this ownership applies (acquisition or incorporation date).", True, "date", width=12),
            Col("end_date", "Last day; blank = still owned.", False, "date", width=12),
            Col("ownership_pct", "Parent's share, 0..100.", True, "float", width=10),
            Col("consolidation_method", "full, proportional, equity or none.", True, "select", ("full", "proportional", "equity", "none"), width=12),
            Col("owner_entity", "The entity whose node HOLDS this share. Blank = the tree parent of the owned node (the group's own node only for a node directly under it). Fill it when a subsidiary or a joint venture is held by another entity, or by two: one row per holder.", False, loader=True, width=12),
        ),
        key=("consolidation_group", "data_area_id", "owner_entity", "effective_date"), submit=True,
        notes=("The root group takes no row: nobody owns the top.",
               "A later change is a new row from its own date; the loader never edits a submitted row.",
               "Two holders of one entity are two rows, one per owner_entity (konsol#117)."),
    ),
    Sheet(
        "Method_Declarations", "Consolidation Group",
        "The method a group applies to an entity its ownership links reach by more than one path. Child rows of the group's own node (blank data_area_id); effective-dated.",
        (
            Col("consolidation_group", "The group whose node carries the declaration.", True, width=14),
            Col("data_area_id", "The entity the declaration is for.", True, width=12),
            Col("consolidation_method", "full or equity (proportional is refused until konsol#117 pair 3).", True, "select", ("full", "equity"), width=12),
            Col("effective_date", "First day this method applies.", True, "date", width=12),
            Col("end_date", "Last day; blank = open.", False, "date", width=12),
            Col("reason", "Required: the arrangement, the holders and the standard, e.g. joint control, IFRS 11.7.", True, width=40),
        ),
        key=("consolidation_group", "data_area_id", "effective_date"),
        notes=("Needed only when an entity is reached by more than one ownership path, or the paths' sum exceeds 50% without an all-full path (konsol#117): the build names the entity in assert_method_declared_for_multi_path until it is declared.",
               "Rows are merged into the group node's method_declarations table by (data_area_id, effective_date): the loader adds missing rows, leaves matching ones, never deletes."),
    ),
    Sheet(
        "FX_Rates", "Group Exchange Rate",
        "Governed translation rates: one Closing and one Average rate per period from each entity currency INTO each group reporting currency. Submitted (approved) on load.",
        (
            Col("to_currency", "Group reporting currency.", True, width=10),
            Col("from_currency", "Entity currency.", True, width=10),
            Col("fiscal_year", "Fiscal year.", True, "int", width=10),
            Col("fiscal_period", "Fiscal period.", True, "int", width=10),
            Col("rate_type", "Closing or Average.", True, "select", ("Closing", "Average"), width=10),
            Col("quote", "Units of to_currency per quoted_per units of from_currency, e.g. 0.955 (EUR per 100 INR).", True, "float", width=12),
            Col("quoted_per", "1, 10, 100, 1000 or 10000 units of from_currency.", True, "select", ("1", "10", "100", "1000", "10000"), width=10),
            Col("change_reason", "Optional note (source of the rate).", False, width=30),
        ),
        key=("to_currency", "from_currency", "fiscal_year", "fiscal_period", "rate_type"), submit=True,
        notes=("A currency equal to the group currency needs no row (translates at 1).",
               "A missing rate stops the build by name; there is no fallback."),
    ),
    Sheet(
        "Historical_Equity_Rates", "Historical Equity Rate",
        "IAS 21: the frozen rate for each equity account of each foreign entity (share capital, share premium). Submitted on load.",
        (
            Col("consolidation_group", "Group code whose translation the rate applies to (the group whose reporting currency differs from the entity's).", True, width=14),
            Col("data_area_id", "entity_code.", True, width=12),
            Col("main_account", "Equity account with fx_method = historical.", True, width=12),
            Col("rate_date", "Date the equity was contributed or acquired.", True, "date", width=12),
            Col("historical_rate", "TRUE rate: units of group currency per 1 unit of entity currency on that date.", True, "float", width=12),
        ),
        key=("consolidation_group", "data_area_id", "main_account"), submit=True,
    ),
    Sheet(
        "Consolidation_Journals", "Consolidation Journal",
        "Manual consolidation entries the templates do not produce, e.g. the opening elimination of the parent's investments in subsidiaries against their share capital on first consolidation. Lines are on CJ_Lines, joined by journal_ref. Approved on load.",
        (
            Col("journal_ref", "A short code of your own, unique per group and period, that the CJ_Lines rows use to name this journal, e.g. CJ-2026-01-INV. It is the journal's natural key: the loader stores it as a leading [code] on the description and finds the journal by it, so rewording the description never creates a second journal.", True, width=18, loader=True),
            Col("consolidation_group", "The group's ROOT code (as on Consolidation_Groups).", True, width=14),
            Col("adjustment_type", "topside or reclassification.", True, "select", ("topside", "reclassification"), width=14),
            Col("fiscal_year", "Fiscal year the journal posts in.", True, "int", width=10),
            Col("fiscal_period", "Fiscal period the journal posts in (must be open).", True, "int", width=10),
            Col("currency", "The group's reporting currency: the currency every line is in. konsol sets this from the root on save and refuses lines in any other currency.", True, width=10),
            Col("description", "What the journal does. Free text; the loader prefixes it with [journal_ref].", True, width=50),
            Col("reverse_fiscal_year", "Optional: year of the period the journal auto-reverses in.", False, "int", width=10),
            Col("reverse_fiscal_period", "Optional: period it auto-reverses in.", False, "int", width=10),
        ),
        key=("consolidation_group", "fiscal_year", "fiscal_period", "journal_ref"), submit=True, workflow=True,
        notes=("Lines are in the group currency; debits must equal credits.",
               "The journal posts as a movement in its period and stays in the balance sheet from then on (unless reversed)."),
    ),
    Sheet(
        "CJ_Lines", "Consolidation Journal Line",
        "The lines of each consolidation journal (child table `lines` of Consolidation Journal): entity, account, debit or credit in the group currency.",
        (
            Col("journal_ref", "journal_ref of the Consolidation_Journals row.", True, width=18, loader=True),
            Col("data_area_id", "entity_code the line is booked against.", True, width=12),
            Col("main_account", "Published posting account.", True, width=12),
            Col("debit_amount", "Debit, in the group currency. Blank or 0 when the line is a credit.", False, "float", width=14),
            Col("credit_amount", "Credit, in the group currency. Blank or 0 when the line is a debit.", False, "float", width=14),
            Col("description", "Optional.", False, width=40),
        ),
        key=("journal_ref", "data_area_id", "main_account"), parent_sheet="Consolidation_Journals", table_field="lines",
    ),
    Sheet(
        "Business_Combinations", "Business Combination",
        "Acquisitions: one row per deal in which a group obtains control of an entity. The deal's consideration, acquired balance sheet and costs are on the BC_* sheets, joined by deal_ref. Submitted (approved) on load.",
        (
            Col("deal_ref", "A short code of your own that the BC_Consideration, BC_Acquired_Balances and BC_Costs rows use to name this deal, e.g. ACQ-ABCZ-2024. Loader-only, never sent.", True, width=18, loader=True),
            Col("consolidation_group", "The acquiring group's ROOT code (as on Consolidation_Groups).", True, width=14),
            Col("acquired_entity", "entity_code of the entity acquired.", True, width=14),
            Col("acquisition_date", "The day control was obtained. Date it on the FIRST day of a declared period (konsolidat#278: the ownership window tests the period's first day).", True, "date", width=12),
            Col("share_acquired_pct", "Share acquired, 0..100. Any share from 0 to 100; below 100 the minority is the NCI line (IFRS 10).", True, "float", width=10),
            Col("consideration_currency", "ISO code the consideration is measured in.", True, width=10),
            Col("acquirer_entity", "The entity whose node acquires. Blank = the acquired node's tree parent.", False, width=14, loader=True),
            Col("nci_measurement_override", "Blank = the root's goodwill_method; partial or full overrides it for this deal.", False, "select", ("", "partial", "full"), width=12),
            Col("nci_fair_value", "Fair value of the non-controlling interest (full method only).", False, "float", width=14),
            Col("fair_value_adjustment_total", "Must equal the sum of fair_value_adjustment on this deal's BC_Acquired_Balances rows; konsol refuses the approval otherwise. Blank = none.", False, "float", width=14),
            Col("description", "Optional.", False, width=40),
        ),
        key=("consolidation_group", "acquired_entity", "acquisition_date"), submit=True, workflow=True,
        notes=("Approval CREATES the acquired entity's Ownership Period from acquisition_date: Ownership_Periods must NOT carry a row for it.",
               "The acquired balance sheet (BC_Acquired_Balances) is the entity's balances at the last period-end BEFORE the acquisition period: the warehouse measures the deal there and carries the entity's own movements from the acquisition period on (konsol#406).",
               "Loads after the FX rates, the root policy and the ownership periods: the deal needs the Closing rate of its period and the root's journal accounts to exist."),
    ),
    Sheet(
        "BC_Consideration", "Business Combination Consideration",
        "What was paid for each acquisition, by component (child table `consideration` of Business Combination). At least one row per deal.",
        (
            Col("deal_ref", "deal_ref of the Business_Combinations row.", True, width=18, loader=True),
            Col("component", "Cash, Deferred, Contingent, Equity instruments, Previously held interest or Other.", True, "select",
                ("Cash", "Deferred", "Contingent", "Equity instruments", "Previously held interest", "Other"), width=20),
            Col("amount", "Amount of this component.", True, "float", width=14),
            Col("currency", "ISO code of the amount.", True, width=10),
            Col("settlement_date", "When this component is (or was) settled.", False, "date", width=12),
            Col("description", "Optional.", False, width=40),
        ),
        key=("deal_ref", "component"), parent_sheet="Business_Combinations", table_field="consideration",
    ),
    Sheet(
        "BC_Acquired_Balances", "Business Combination Acquired Balance",
        "The acquired entity's balance sheet at acquisition, one row per account (child table `acquired_balances` of Business Combination).",
        (
            Col("deal_ref", "deal_ref of the Business_Combinations row.", True, width=18, loader=True),
            Col("main_account", "Published posting account.", True, width=12),
            Col("book_amount", "In the entity's currency: debit positive, credit negative. The lines net to the entity's equity at acquisition; the P&L result to date is folded into the retained-earnings account.", True, "float", width=14),
            Col("fair_value_adjustment", "Fair value uplift (+) or write-down (-) on this account. The deal's fair_value_adjustment_total must equal the sum.", False, "float", width=14),
            Col("note", "Optional.", False, width=30),
        ),
        key=("deal_ref", "main_account"), parent_sheet="Business_Combinations", table_field="acquired_balances",
    ),
    Sheet(
        "BC_Costs", "Business Combination Cost",
        "Acquisition-related costs (child table `costs` of Business Combination). The root's acquisition_costs_treatment says whether they are expensed or capitalised.",
        (
            Col("deal_ref", "deal_ref of the Business_Combinations row.", True, width=18, loader=True),
            Col("kind", "Legal, Advisory, Due diligence or Other.", True, "select", ("Legal", "Advisory", "Due diligence", "Other"), width=14),
            Col("amount", "Amount.", True, "float", width=14),
            Col("currency", "ISO code of the amount.", True, width=10),
            Col("description", "Optional.", False, width=40),
        ),
        key=("deal_ref", "kind"), parent_sheet="Business_Combinations", table_field="costs",
    ),
    Sheet(
        "Business_Disposals", "Business Disposal",
        "Disposals: one row per deal in which a group sells an entity. The proceeds are on BD_Proceeds, joined by deal_ref. Submitted (approved) on load.",
        (
            Col("deal_ref", "A short code of your own that the BD_Proceeds rows use to name this deal, e.g. DISP-ABDK-2026. Loader-only, never sent.", True, width=18, loader=True),
            Col("consolidation_group", "The selling group's ROOT code (as on Consolidation_Groups).", True, width=14),
            Col("disposed_entity", "entity_code of the entity sold.", True, width=14),
            Col("disposal_date", "Date it inside the period whose balances are derecognised. It must equal the Ownership Period's last day of ownership.", True, "date", width=12),
            Col("disposer_entity", "The entity whose node sells. Blank = the sold node's tree parent.", False, width=14, loader=True),
            Col("share_disposed_pct", "Must equal the current holding: only full disposals are supported today.", True, "float", width=10),
            Col("retained_interest_pct", "Share kept after the sale. Must be 0 today.", False, "float", width=10),
            Col("proceeds_currency", "ISO code the proceeds are measured in.", True, width=10),
            Col("description", "Optional.", False, width=40),
        ),
        key=("consolidation_group", "disposed_entity", "disposal_date"), submit=True, workflow=True,
        notes=("Approval ENDS the Ownership Period covering disposal_date on that date; the entity leaves the group from the next period.",
               "Loads after the FX rates and the ownership periods: the period being ended must already be submitted, and the deal needs the Closing rate of its period."),
    ),
    Sheet(
        "BD_Proceeds", "Business Disposal Proceeds",
        "What was received for each disposal, by component (child table `proceeds` of Business Disposal). At least one row per deal.",
        (
            Col("deal_ref", "deal_ref of the Business_Disposals row.", True, width=18, loader=True),
            Col("component", "Cash, Deferred, Contingent or Other.", True, "select", ("Cash", "Deferred", "Contingent", "Other"), width=14),
            Col("amount", "Amount of this component.", True, "float", width=14),
            Col("currency", "ISO code of the amount.", True, width=10),
            Col("settlement_date", "When this component is (or was) settled.", False, "date", width=12),
            Col("description", "Optional.", False, width=40),
        ),
        key=("deal_ref", "component"), parent_sheet="Business_Disposals", table_field="proceeds",
    ),
    Sheet(
        "Trial_Balance", "Trial Balance Upload",
        "The bulk trial-balance file format (reference only on this sheet: real files are separate workbooks, one per period, data on the FIRST sheet).",
        tuple(
            [Col("data_area_id", "entity_code. Aliases accepted: entity, company.", True, width=12),
             Col("fiscal_year", "Fiscal year.", True, "int", width=8),
             Col("fiscal_period", "Fiscal period number.", True, "int", width=8),
             Col("main_account", "Published posting account.", True, width=10),
             Col("debit", "Debit balance (positive). Blank or 0 when the row is a credit.", True, "float", width=14),
             Col("credit", "Credit balance (positive). Blank or 0 when the row is a debit.", True, "float", width=14),
             Col("currency", "ISO code of the amounts: must equal the entity's functional_currency on every row.", True, width=8),
             Col("description", "Optional.", False, width=30),
             Col("partner_data_area_id", "Other group entity on an intercompany row; blank for third parties.", False, width=12),
             Col("amount_basis", "Period movement, Year-to-date movement or Period-end balance. One basis per entity-period, and per entity across its history.", False, "select", AMOUNT_BASES, width=18),
             Col("dim_<name>", "One column per Published dimension with in_trial_balance = 1, header = dimension_name exactly. Blank cell = no value.", False, width=14)]
        ),
        key=("data_area_id", "fiscal_year", "fiscal_period", "main_account"),
        notes=("One row per (account, partner, dimension values). Debits equal credits exactly per entity-period, in the currency's minor unit.",
               "Every account must be in the group chart; every partner must be a legal entity other than the row's own."),
    ),
)

#: Sheets the loader writes, in dependency order.
LOAD_ORDER = tuple(s.name for s in SHEETS if s.name != "Trial_Balance")

BY_NAME = {s.name: s for s in SHEETS}

#: Child-table sheets by the sheet they nest into: {parent sheet name: (child Sheet, ...)}.
#: A child sheet is never loaded on its own; the loader attaches its rows to the parent document.
CHILD_SHEETS = {
    p.name: tuple(c for c in SHEETS if c.parent_sheet == p.name)
    for p in SHEETS if any(c.parent_sheet == p.name for c in SHEETS)
}


def link_column(parent: Sheet, child: Sheet) -> str:
    """The loader-only column a child sheet's rows share with their parent row
    (deal_ref, journal_ref): the first loader=True column present on both."""
    return next(c.name for c in parent.cols if c.loader and c.name in child.fieldnames)


# ---------------------------------------------------------------------------
# workbook writer
# ---------------------------------------------------------------------------

FONT = "Arial"


def write_workbook(path, rows_by_sheet, *, title, intro_lines, example_rows=None, input_fill=False):
    """Write the onboarding workbook: a README sheet, then one sheet per Sheet.

    rows_by_sheet: {sheet name: [dict]} data rows.
    example_rows:  {sheet name: [dict]} rows shown grey+italic (template only).
    input_fill:    shade data cells yellow (template only: 'fill these in').
    """
    from openpyxl import Workbook
    from openpyxl.comments import Comment
    from openpyxl.styles import Alignment, Font, PatternFill
    from openpyxl.utils import get_column_letter
    from openpyxl.worksheet.datavalidation import DataValidation

    example_rows = example_rows or {}
    wb = Workbook()
    readme = wb.active
    readme.title = "README"
    _write_readme(readme, title, intro_lines, rows_by_sheet, example_rows)

    head_font = Font(name=FONT, bold=True, color="FFFFFF", size=10)
    head_fill = PatternFill("solid", fgColor="1F3864")
    req_fill = PatternFill("solid", fgColor="C00000")
    body_font = Font(name=FONT, size=10)
    ex_font = Font(name=FONT, size=10, italic=True, color="7F7F7F")
    yellow = PatternFill("solid", fgColor="FFF2CC")
    grey = PatternFill("solid", fgColor="F2F2F2")

    for sheet in SHEETS:
        ws = wb.create_sheet(sheet.name)
        cols = list(sheet.cols)
        if sheet.name == "Trial_Balance":
            # the placeholder dim_<name> column is replaced by the real dims the data carries
            data = rows_by_sheet.get(sheet.name) or example_rows.get(sheet.name) or []
            dims = sorted({k for r in data for k in r if k.startswith("dim_")})
            cols = [c for c in cols if c.name != "dim_<name>"] + [
                Col(d, "Dimension value for %s (blank = none)." % d, False, width=16) for d in dims]
        for i, c in enumerate(cols, 1):
            cell = ws.cell(row=1, column=i, value=c.name)
            cell.font = head_font
            cell.fill = req_fill if c.required else head_fill
            cell.alignment = Alignment(vertical="center", wrap_text=True)
            text = c.help
            if c.options:
                text += "\nOne of: " + ", ".join(o if o else "(blank)" for o in c.options)
            if c.required:
                text += "\nREQUIRED."
            cell.comment = Comment(text, "konsol template")
            ws.column_dimensions[get_column_letter(i)].width = c.width
            if c.options and len(c.options) <= 12:
                dv = DataValidation(type="list", formula1='"%s"' % ",".join(c.options), allow_blank=True)
                dv.error = "Pick one of the listed values"
                ws.add_data_validation(dv)
                dv.add("%s2:%s5000" % (get_column_letter(i), get_column_letter(i)))
        ws.row_dimensions[1].height = 30
        ws.freeze_panes = "A2"
        ws.auto_filter.ref = "A1:%s1" % get_column_letter(len(cols))

        r = 2
        for row in example_rows.get(sheet.name, []):
            for i, c in enumerate(cols, 1):
                cell = ws.cell(row=r, column=i, value=_cell_value(row.get(c.name), c))
                cell.font = ex_font
                cell.fill = grey
                _number_format(cell, c)
            r += 1
        for row in rows_by_sheet.get(sheet.name, []):
            for i, c in enumerate(cols, 1):
                cell = ws.cell(row=r, column=i, value=_cell_value(row.get(c.name), c))
                cell.font = body_font
                if input_fill:
                    cell.fill = yellow
                _number_format(cell, c)
            r += 1
        if input_fill and r < 30:
            # a visible run of empty input rows so the sheet reads as a form
            for rr in range(r, r + 20):
                for i, c in enumerate(cols, 1):
                    ws.cell(row=rr, column=i).fill = yellow
    wb.save(path)
    return path


def _cell_value(value, col):
    if value is None or value == "":
        return None
    if col.kind == "date":
        return str(value)[:10]
    if col.kind == "check":
        return int(bool(int(value))) if str(value).strip() not in ("", "0", "false", "False") else 0
    if col.kind in ("int",):
        return int(value)
    if col.kind == "float":
        return float(value)
    return str(value)


def _number_format(cell, col):
    if col.kind == "float" and col.name in ("debit", "credit", "debit_amount", "credit_amount", "amount", "book_amount",
                                            "fair_value_adjustment", "fair_value_adjustment_total", "nci_fair_value"):
        cell.number_format = "#,##0.00"
    elif col.kind == "float":
        cell.number_format = "0.000000"
    elif col.kind == "int":
        cell.number_format = "0"


def _write_readme(ws, title, intro_lines, rows_by_sheet, example_rows):
    from openpyxl.styles import Alignment, Font, PatternFill

    ws.column_dimensions["A"].width = 30
    ws.column_dimensions["B"].width = 34
    ws.column_dimensions["C"].width = 14
    ws.column_dimensions["D"].width = 90
    h1 = Font(name=FONT, bold=True, size=16, color="1F3864")
    h2 = Font(name=FONT, bold=True, size=12, color="1F3864")
    body = Font(name=FONT, size=10)
    bold = Font(name=FONT, size=10, bold=True)
    wrap = Alignment(wrap_text=True, vertical="top")
    r = 1
    ws.cell(row=r, column=1, value=title).font = h1
    r += 2
    for line in intro_lines:
        c = ws.cell(row=r, column=1, value=line)
        c.font = body
        c.alignment = wrap
        ws.merge_cells(start_row=r, start_column=1, end_row=r, end_column=4)
        ws.row_dimensions[r].height = 15 * max(1, len(line) // 150 + 1)
        r += 1
    r += 1
    ws.cell(row=r, column=1, value="Legend").font = h2
    r += 1
    legend = (
        ("1F3864", "FFFFFF", "Column header: a konsol fieldname. Hover for help; red headers are required."),
        ("FFF2CC", None, "Yellow cells: fill these in (template only)."),
        ("F2F2F2", "7F7F7F", "Grey italic rows: examples of the expected format. Codes start with EXAMPLE_; delete them before loading."),
    )
    for fill, font_color, text in legend:
        c = ws.cell(row=r, column=1, value="sample")
        c.fill = PatternFill("solid", fgColor=fill)
        c.font = Font(name=FONT, size=10, color=font_color) if font_color else body
        ws.cell(row=r, column=2, value=text).font = body
        ws.merge_cells(start_row=r, start_column=2, end_row=r, end_column=4)
        r += 1
    r += 1
    ws.cell(row=r, column=1, value="Sheets, in load order").font = h2
    r += 1
    for j, head in enumerate(("Sheet", "konsol doctype", "Rows here", "What it holds / rules"), 1):
        c = ws.cell(row=r, column=j, value=head)
        c.font = bold
        c.fill = PatternFill("solid", fgColor="D9E1F2")
    r += 1
    for sheet in SHEETS:
        n = len(rows_by_sheet.get(sheet.name, [])) or (len(example_rows.get(sheet.name, [])) and "examples") or 0
        ws.cell(row=r, column=1, value=sheet.name).font = bold
        ws.cell(row=r, column=2, value=sheet.doctype).font = body
        ws.cell(row=r, column=3, value=n).font = body
        text = sheet.purpose
        if sheet.submit:
            text += " Rows are submitted (approved) when loaded."
        if sheet.parent_sheet:
            text += " Rows are nested into their %s row (matched on %s) as the `%s` table; the sheet is not loaded on its own." % (
                sheet.parent_sheet, link_column(BY_NAME[sheet.parent_sheet], sheet), sheet.table_field)
        if sheet.notes:
            text += "\n" + "\n".join("- " + n for n in sheet.notes)
        c = ws.cell(row=r, column=4, value=text)
        c.font = body
        c.alignment = wrap
        ws.row_dimensions[r].height = 15 * (text.count("\n") + 1 + len(text) // 110)
        r += 1
    r += 1
    ws.cell(row=r, column=1, value="Conventions").font = h2
    r += 1
    for line in (
        "Codes (entities, accounts, dimensions, groups) are upper-case, no spaces, and never change once trial balances post to them.",
        "Dates are ISO (YYYY-MM-DD). Flags are 1 or 0. Select columns offer a drop-down with the allowed values.",
        "Header row = fieldnames: each sheet can also be imported one at a time with Frappe Desk > Data Import, or all together with konsol_load.py (see README.md next to this file).",
        "Trial balances are NOT in this workbook: one file per period (CSV or .xlsx, data on the first sheet) in the format shown on the Trial_Balance sheet.",
    ):
        c = ws.cell(row=r, column=1, value=line)
        c.font = body
        c.alignment = wrap
        ws.merge_cells(start_row=r, start_column=1, end_row=r, end_column=4)
        ws.row_dimensions[r].height = 30
        r += 1
