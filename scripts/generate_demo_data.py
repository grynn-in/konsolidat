#!/usr/bin/env python3
"""
Generate synthetic demo data for Konsolidat one-click deploy.

Creates a fictional 3-entity manufacturing group (Alpine Manufacturing)
with 12 months of GL data, budget, exchange rates, and trial balance.

Output: clickhouse/demo-data.sql
"""

import uuid
import random
from datetime import date, timedelta
from decimal import Decimal

random.seed(42)  # reproducible

NOW = "2024-12-31 23:59:59.000"
META = "{}"
GEN = 0

# ── Company structure ──────────────────────────────────────────────
ENTITIES = [
    ("AMHQ", "Alpine Manufacturing HQ", "CH", "CHF", "CHF", ""),
    ("AMUS", "Alpine Manufacturing US", "US", "USD", "CHF", "P00001"),
    ("AMDE", "Alpine Manufacturing DE", "DE", "EUR", "CHF", "P00002"),
]

# ── Chart of Accounts ─────────────────────────────────────────────
ACCOUNTS = [
    # (id, name, type, category, debit_credit_default, chart)
    ("1010", "Cash and Cash Equivalents", "BalanceSheet", "Cash", "Debit", "AMG"),
    ("1100", "Accounts Receivable", "BalanceSheet", "AccountsReceivable", "Debit", "AMG"),
    ("1200", "Inventory", "BalanceSheet", "Inventory", "Debit", "AMG"),
    ("1500", "Fixed Assets", "BalanceSheet", "FixedAssets", "Debit", "AMG"),
    ("1510", "Accumulated Depreciation", "BalanceSheet", "FixedAssets", "Credit", "AMG"),
    ("2010", "Accounts Payable", "BalanceSheet", "AccountsPayable", "Credit", "AMG"),
    ("2100", "Accrued Liabilities", "BalanceSheet", "AccruedLiabilities", "Credit", "AMG"),
    ("2500", "Long-term Debt", "BalanceSheet", "LongTermDebt", "Credit", "AMG"),
    ("3010", "Share Capital", "BalanceSheet", "Equity", "Credit", "AMG"),
    ("3100", "Retained Earnings", "BalanceSheet", "Equity", "Credit", "AMG"),
    ("4010", "Product Revenue", "ProfitAndLoss", "Revenue", "Credit", "AMG"),
    ("4020", "Service Revenue", "ProfitAndLoss", "Revenue", "Credit", "AMG"),
    ("4030", "Intercompany Revenue", "ProfitAndLoss", "Revenue", "Credit", "AMG"),
    ("5010", "Cost of Goods Sold", "ProfitAndLoss", "COGS", "Debit", "AMG"),
    ("5030", "Intercompany Expense", "ProfitAndLoss", "COGS", "Debit", "AMG"),
    ("6010", "Salaries and Wages", "ProfitAndLoss", "OperatingExpense", "Debit", "AMG"),
    ("6020", "Rent Expense", "ProfitAndLoss", "OperatingExpense", "Debit", "AMG"),
    ("6030", "Depreciation Expense", "ProfitAndLoss", "OperatingExpense", "Debit", "AMG"),
    ("6040", "Marketing Expense", "ProfitAndLoss", "OperatingExpense", "Debit", "AMG"),
    ("6050", "Travel Expense", "ProfitAndLoss", "OperatingExpense", "Debit", "AMG"),
    ("6060", "Utilities", "ProfitAndLoss", "OperatingExpense", "Debit", "AMG"),
    ("6070", "Professional Services", "ProfitAndLoss", "OperatingExpense", "Debit", "AMG"),
    ("7010", "Interest Income", "ProfitAndLoss", "OtherIncome", "Credit", "AMG"),
    ("7020", "Interest Expense", "ProfitAndLoss", "OtherExpense", "Debit", "AMG"),
]

# Monthly revenue by entity (base, with ±10% seasonal variance)
REVENUE_BASE = {"AMHQ": 500000, "AMUS": 800000, "AMDE": 600000}
SEASONAL = [0.85, 0.90, 0.95, 1.00, 1.05, 1.10, 1.15, 1.10, 1.05, 1.00, 0.95, 0.90]

# Cost centers per entity
COST_CENTERS = {"AMHQ": "HQ", "AMUS": "SALES", "AMDE": "PROD"}
DEPARTMENTS = {"AMHQ": "MGMT", "AMUS": "SALES", "AMDE": "OPS"}
BIZ_UNITS = {"AMHQ": "CORP", "AMUS": "SERVICES", "AMDE": "MANUFACTURING"}

# FX rates (monthly average CHF per 1 foreign unit)
# CHF/USD and CHF/EUR for 2024
FX_CHF_USD = [0.8550, 0.8620, 0.8780, 0.8900, 0.9050, 0.8980,
              0.8850, 0.8720, 0.8610, 0.8550, 0.8700, 0.8800]
FX_CHF_EUR = [0.9350, 0.9400, 0.9450, 0.9500, 0.9550, 0.9480,
              0.9420, 0.9380, 0.9350, 0.9300, 0.9400, 0.9500]


def uid():
    return str(uuid.UUID(int=random.getrandbits(128), version=4))


def dim_json(acct, cc, dept, bu):
    """D365-style LedgerDimensionValuesJson (single-quoted in raw data)."""
    return (
        f"[{{'MAINACCOUNT': '{acct}', 'COSTCENTER': '{cc}', "
        f"'DEPARTMENT': '{dept}', 'BUSINESSUNIT': '{bu}'}}]"
    )


def esc(s):
    """Escape single quotes for ClickHouse SQL string values."""
    return str(s).replace("'", "\\'")


lines = []
w = lines.append


def section(title):
    w(f"\n-- {'=' * 70}")
    w(f"-- {title}")
    w(f"-- {'=' * 70}\n")


# ── Preamble ──────────────────────────────────────────────────────
w("-- Konsolidat Demo Data: Alpine Manufacturing Group")
w("-- Generated synthetic data for one-click deploy demo")
w("-- 3 legal entities (CHF, USD, EUR), 12 months FY2024")
w("")
w("CREATE DATABASE IF NOT EXISTS epm_raw;")

# ── Table creation (Airbyte-compatible schemas) ───────────────────
section("Table Creation (Airbyte-compatible schemas)")

TABLES = {
    "main_accounts": """
    `_airbyte_raw_id` String,
    `_airbyte_extracted_at` DateTime64(3),
    `_airbyte_meta` String,
    `_airbyte_generation_id` UInt32,
    `Name` Nullable(String),
    `IsSuspended` Nullable(String),
    `MainAccountId` Nullable(String),
    `ChartOfAccounts` Nullable(String),
    `MainAccountType` Nullable(String),
    `DebitCreditDefault` Nullable(String),
    `MainAccountCategory` Nullable(String)""",

    "main_account_categories": """
    `_airbyte_raw_id` String,
    `_airbyte_extracted_at` DateTime64(3),
    `_airbyte_meta` String,
    `_airbyte_generation_id` UInt32,
    `Closed` Nullable(String),
    `Description` Nullable(String),
    `ReferenceId` Nullable(String),
    `MainAccountType` Nullable(String),
    `MainAccountCategory` Nullable(String)""",

    "legal_entities": """
    `_airbyte_raw_id` String,
    `_airbyte_extracted_at` DateTime64(3),
    `_airbyte_meta` String,
    `_airbyte_generation_id` UInt32,
    `Name` Nullable(String),
    `LegalEntityId` Nullable(String),
    `AddressCountryRegionId` Nullable(String),
    `PartyNumber` Nullable(String)""",

    "ledgers": """
    `_airbyte_raw_id` String,
    `_airbyte_extracted_at` DateTime64(3),
    `_airbyte_meta` String,
    `_airbyte_generation_id` UInt32,
    `Name` Nullable(String),
    `LegalEntityId` Nullable(String),
    `ChartOfAccountsId` Nullable(String),
    `ReportingCurrency` Nullable(String),
    `AccountingCurrency` Nullable(String)""",

    "fiscal_calendar_years": """
    `_airbyte_raw_id` String,
    `_airbyte_extracted_at` DateTime64(3),
    `_airbyte_meta` String,
    `_airbyte_generation_id` UInt32,
    `EndDate` Nullable(String),
    `Calendar` Nullable(String),
    `StartDate` Nullable(String),
    `FiscalYear` Nullable(String),
    `Description` Nullable(String)""",

    "exchange_rates": """
    `_airbyte_raw_id` String,
    `_airbyte_extracted_at` DateTime64(3),
    `_airbyte_meta` String,
    `_airbyte_generation_id` UInt32,
    `Rate` Nullable(Decimal(38, 9)),
    `EndDate` Nullable(String),
    `StartDate` Nullable(String),
    `ToCurrency` Nullable(String),
    `FromCurrency` Nullable(String),
    `RateTypeName` Nullable(String),
    `ConversionFactor` Nullable(String)""",

    "exchange_rate_types": """
    `_airbyte_raw_id` String,
    `_airbyte_extracted_at` DateTime64(3),
    `_airbyte_meta` String,
    `_airbyte_generation_id` UInt32,
    `Name` Nullable(String),
    `Description` Nullable(String)""",

    "dimension_attributes": """
    `_airbyte_raw_id` String,
    `_airbyte_extracted_at` DateTime64(3),
    `_airbyte_meta` String,
    `_airbyte_generation_id` UInt32,
    `DimensionName` Nullable(String),
    `UseValuesFrom` Nullable(String),
    `ReportColumnName` Nullable(String)""",

    "financial_dimension_values": """
    `_airbyte_raw_id` String,
    `_airbyte_extracted_at` DateTime64(3),
    `_airbyte_meta` String,
    `_airbyte_generation_id` UInt32,
    `ActiveTo` Nullable(String),
    `ActiveFrom` Nullable(String),
    `Description` Nullable(String),
    `IsSuspended` Nullable(String),
    `DimensionValue` Nullable(String),
    `FinancialDimension` Nullable(String)""",

    "consolidate_account_groups": """
    `_airbyte_raw_id` String,
    `_airbyte_extracted_at` DateTime64(3),
    `_airbyte_meta` String,
    `_airbyte_generation_id` UInt32,
    `ConsolidationAccountGroup` Nullable(String),
    `ConsolidationAccountGroupName` Nullable(String)""",

    "general_journal_entry_bi_entities": """
    `_airbyte_raw_id` String,
    `_airbyte_extracted_at` DateTime64(3),
    `_airbyte_meta` String,
    `_airbyte_generation_id` UInt32,
    `SourceKey` Nullable(Int64),
    `DocumentDate` Nullable(String),
    `PostingLayer` Nullable(String),
    `JournalNumber` Nullable(String),
    `AccountingDate` Nullable(String),
    `DocumentNumber` Nullable(String),
    `JournalCategory` Nullable(String),
    `SubledgerVoucher` Nullable(String),
    `FiscalCalendarYear` Nullable(Int64),
    `FiscalCalendarPeriod` Nullable(Int64),
    `SubledgerVoucherDataAreaId` Nullable(String)""",

    "general_journal_account_entry_bi_entities": """
    `_airbyte_raw_id` String,
    `_airbyte_extracted_at` DateTime64(3),
    `_airbyte_meta` String,
    `_airbyte_generation_id` UInt32,
    `Text` Nullable(String),
    `IsCredit` Nullable(String),
    `SourceKey` Nullable(Int64),
    `PostingType` Nullable(String),
    `LedgerAccount` Nullable(String),
    `AccountingDate` Nullable(String),
    `GeneralJournalEntry` Nullable(Int64),
    `ReportingCurrencyAmount` Nullable(Decimal(38, 9)),
    `TransactionCurrencyCode` Nullable(String),
    `AccountingCurrencyAmount` Nullable(Decimal(38, 9)),
    `LedgerDimensionValuesJson` Nullable(String),
    `TransactionCurrencyAmount` Nullable(Decimal(38, 9))""",

    "budget_register_entries": """
    `_airbyte_raw_id` String,
    `_airbyte_extracted_at` DateTime64(3),
    `_airbyte_meta` String,
    `_airbyte_generation_id` UInt32,
    `Date` Nullable(String),
    `Status` Nullable(String),
    `Comment` Nullable(String),
    `BudgetCode` Nullable(String),
    `Department` Nullable(String),
    `dataAreaId` Nullable(String),
    `EntryNumber` Nullable(String),
    `BusinessUnit` Nullable(String),
    `CurrencyCode` Nullable(String),
    `BudgetModelId` Nullable(String),
    `LegalEntityId` Nullable(String),
    `ReasonComment` Nullable(String),
    `DimensionDisplayValue` Nullable(String),
    `AccountingCurrencyAmount` Nullable(Decimal(38, 9)),
    `IncludeInCashFlowForecast` Nullable(String),
    `TransactionCurrencyAmount` Nullable(Decimal(38, 9))""",

    "trial_balance_fiscal_year_snapshots": """
    `_airbyte_raw_id` String,
    `_airbyte_extracted_at` DateTime64(3),
    `_airbyte_meta` String,
    `_airbyte_generation_id` UInt32,
    `YearName` Nullable(String),
    `LedgerName` Nullable(String),
    `AmountDebit` Nullable(Decimal(38, 9)),
    `AmountCredit` Nullable(Decimal(38, 9)),
    `EndingBalance` Nullable(Decimal(38, 9)),
    `OpeningBalance` Nullable(Decimal(38, 9)),
    `DimensionValue1` Nullable(String),
    `PeriodStartDate` Nullable(String)""",
}

for tname, cols in TABLES.items():
    w(f"CREATE TABLE IF NOT EXISTS epm_raw.{tname}")
    w(f"({cols}")
    w(") ENGINE = MergeTree ORDER BY _airbyte_raw_id;")
    w("")

# ── Helper to build INSERT rows ──────────────────────────────────
def val(v):
    """Format a value for SQL INSERT."""
    if v is None:
        return "NULL"
    if isinstance(v, (int, float, Decimal)):
        return str(v)
    return f"'{esc(v)}'"


# ── Main Accounts ─────────────────────────────────────────────────
section("Main Accounts (Chart of Accounts)")
w("INSERT INTO epm_raw.main_accounts VALUES")
rows = []
for acct_id, name, atype, cat, dc, chart in ACCOUNTS:
    rows.append(
        f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, "
        f"{val(name)}, 'No', {val(acct_id)}, {val(chart)}, "
        f"{val(atype)}, {val(dc)}, {val(cat)})"
    )
w(",\n".join(rows) + ";")

# ── Main Account Categories ───────────────────────────────────────
section("Main Account Categories")
CATEGORIES = [
    ("CAT001", "Cash", "Cash and bank accounts", "BalanceSheet"),
    ("CAT002", "AccountsReceivable", "Trade receivables", "BalanceSheet"),
    ("CAT003", "Inventory", "Raw materials and finished goods", "BalanceSheet"),
    ("CAT004", "FixedAssets", "Property plant and equipment", "BalanceSheet"),
    ("CAT005", "AccountsPayable", "Trade payables", "BalanceSheet"),
    ("CAT006", "AccruedLiabilities", "Accrued expenses", "BalanceSheet"),
    ("CAT007", "LongTermDebt", "Bank loans and bonds", "BalanceSheet"),
    ("CAT008", "Equity", "Share capital and retained earnings", "BalanceSheet"),
    ("CAT009", "Revenue", "Sales revenue", "ProfitAndLoss"),
    ("CAT010", "COGS", "Cost of goods and services sold", "ProfitAndLoss"),
    ("CAT011", "OperatingExpense", "SG&A expenses", "ProfitAndLoss"),
    ("CAT012", "OtherIncome", "Interest and other income", "ProfitAndLoss"),
    ("CAT013", "OtherExpense", "Interest and other expense", "ProfitAndLoss"),
]
w("INSERT INTO epm_raw.main_account_categories VALUES")
rows = []
for ref_id, cat, desc, atype in CATEGORIES:
    rows.append(
        f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, "
        f"'No', {val(desc)}, {val(ref_id)}, {val(atype)}, {val(cat)})"
    )
w(",\n".join(rows) + ";")

# ── Legal Entities ────────────────────────────────────────────────
section("Legal Entities")
w("INSERT INTO epm_raw.legal_entities VALUES")
rows = []
for eid, ename, country, accy, rcy, party in ENTITIES:
    rows.append(
        f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, "
        f"{val(ename)}, {val(eid)}, {val(country)}, {val(party)})"
    )
w(",\n".join(rows) + ";")

# ── Ledgers ───────────────────────────────────────────────────────
section("Ledgers")
w("INSERT INTO epm_raw.ledgers VALUES")
rows = []
for eid, ename, country, accy, rcy, party in ENTITIES:
    rows.append(
        f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, "
        f"{val(ename + ' Ledger')}, {val(eid)}, 'AMG', {val(rcy)}, {val(accy)})"
    )
w(",\n".join(rows) + ";")

# ── Fiscal Calendar ───────────────────────────────────────────────
section("Fiscal Calendar Years")
w("INSERT INTO epm_raw.fiscal_calendar_years VALUES")
w(f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, "
  f"'2024-12-31', 'Standard', '2024-01-01', '2024', 'Fiscal Year 2024');")

# ── Exchange Rate Types ───────────────────────────────────────────
section("Exchange Rate Types")
w("INSERT INTO epm_raw.exchange_rate_types VALUES")
w(f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, 'Default', 'Default exchange rate'),")
w(f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, 'Closing', 'Month-end closing rate'),")
w(f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, 'Average', 'Monthly average rate');")

# ── Exchange Rates ────────────────────────────────────────────────
section("Exchange Rates (Monthly CHF/USD and CHF/EUR)")
w("INSERT INTO epm_raw.exchange_rates VALUES")
rows = []
for month_idx in range(12):
    m = month_idx + 1
    start = f"2024-{m:02d}-01"
    if m == 12:
        end = "2024-12-31"
    else:
        end = f"2024-{m+1:02d}-01"

    # USD → CHF rates (Default + Closing + Average)
    usd_rate = FX_CHF_USD[month_idx]
    for rtype in ["Default", "Closing", "Average"]:
        # Slight variation for closing vs average
        r = usd_rate
        if rtype == "Closing":
            r = round(usd_rate * 1.005, 4)
        elif rtype == "Average":
            r = round(usd_rate * 0.998, 4)
        rows.append(
            f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, "
            f"{r}, {val(end)}, {val(start)}, 'CHF', 'USD', {val(rtype)}, 'Hundred')"
        )

    # EUR → CHF rates
    eur_rate = FX_CHF_EUR[month_idx]
    for rtype in ["Default", "Closing", "Average"]:
        r = eur_rate
        if rtype == "Closing":
            r = round(eur_rate * 1.003, 4)
        elif rtype == "Average":
            r = round(eur_rate * 0.997, 4)
        rows.append(
            f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, "
            f"{r}, {val(end)}, {val(start)}, 'CHF', 'EUR', {val(rtype)}, 'Hundred')"
        )
w(",\n".join(rows) + ";")

# ── Dimension Attributes ─────────────────────────────────────────
section("Dimension Attributes")
w("INSERT INTO epm_raw.dimension_attributes VALUES")
w(f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, 'CostCenter', 'CostCenter', 'CostCenter'),")
w(f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, 'Department', 'Department', 'Department'),")
w(f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, 'BusinessUnit', 'BusinessUnit', 'BusinessUnit');")

# ── Financial Dimension Values ────────────────────────────────────
section("Financial Dimension Values")
DIM_VALUES = [
    ("CostCenter", "HQ", "Headquarters"),
    ("CostCenter", "SALES", "Sales Division"),
    ("CostCenter", "PROD", "Production"),
    ("CostCenter", "ADMIN", "Administration"),
    ("Department", "MGMT", "Management"),
    ("Department", "SALES", "Sales"),
    ("Department", "OPS", "Operations"),
    ("Department", "FINANCE", "Finance"),
    ("Department", "HR", "Human Resources"),
    ("BusinessUnit", "CORP", "Corporate"),
    ("BusinessUnit", "SERVICES", "Services"),
    ("BusinessUnit", "MANUFACTURING", "Manufacturing"),
]
w("INSERT INTO epm_raw.financial_dimension_values VALUES")
rows = []
for dim, dval, desc in DIM_VALUES:
    rows.append(
        f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, "
        f"'2099-12-31', '2024-01-01', {val(desc)}, 'No', {val(dval)}, {val(dim)})"
    )
w(",\n".join(rows) + ";")

# ── Consolidation Account Groups ──────────────────────────────────
section("Consolidation Account Groups")
w("INSERT INTO epm_raw.consolidate_account_groups VALUES")
w(f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, 'AMG', 'Alpine Manufacturing Group');")

# ── GL Journal Entries ────────────────────────────────────────────
section("GL Journal Entry Headers + Lines")

header_key = 1000  # auto-increment SourceKey for headers
line_key = 10000   # auto-increment SourceKey for lines
gl_headers = []
gl_lines = []

# Opening balance entries (Jan 1) — BS accounts only
OPENING_BALANCES = {
    "AMHQ": {
        "1010": 2500000, "1100": 800000, "1200": 1200000,
        "1500": 3000000, "1510": -600000,
        "2010": -500000, "2100": -200000, "2500": -2000000,
        "3010": -3000000, "3100": -1200000,
    },
    "AMUS": {
        "1010": 1800000, "1100": 1200000, "1200": 900000,
        "1500": 2000000, "1510": -400000,
        "2010": -600000, "2100": -300000, "2500": -1500000,
        "3010": -2000000, "3100": -1100000,
    },
    "AMDE": {
        "1010": 1500000, "1100": 900000, "1200": 1100000,
        "1500": 2500000, "1510": -500000,
        "2010": -400000, "2100": -250000, "2500": -1800000,
        "3010": -2500000, "3100": -550000,
    },
}

for entity_id, ename, country, accy, rcy, party in ENTITIES:
    cc = COST_CENTERS[entity_id]
    dept = DEPARTMENTS[entity_id]
    bu = BIZ_UNITS[entity_id]

    # Opening balance journal (period 0 / Jan 1)
    header_key += 1
    hk = header_key
    jnum = f"OB-{entity_id}-2024"
    adate = "2024-01-01"

    gl_headers.append(
        f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, "
        f"{hk}, {val(adate)}, 'Current', {val(jnum)}, {val(adate)}, "
        f"'{jnum}', 'OpeningBalance', '{jnum}', 2024, 1, {val(entity_id)})"
    )

    for acct, bal in OPENING_BALANCES[entity_id].items():
        line_key += 1
        is_credit = "Yes" if bal < 0 else "No"
        amt = abs(bal)
        ledger_acct = f"{acct}-{cc}-{dept}"
        dj = dim_json(acct, cc, dept, bu)

        # Reporting currency amount (convert to CHF for non-CHF entities)
        if accy == "CHF":
            rpt_amt = amt
        elif accy == "USD":
            rpt_amt = round(amt * FX_CHF_USD[0], 2)
        else:
            rpt_amt = round(amt * FX_CHF_EUR[0], 2)

        gl_lines.append(
            f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, "
            f"'Opening balance', {val(is_credit)}, {line_key}, 'Normal', "
            f"{val(ledger_acct)}, {val(adate)}, {hk}, "
            f"{rpt_amt}, {val(accy)}, {amt}, {val(dj)}, {amt})"
        )

    # Monthly operational entries
    for month_idx in range(12):
        m = month_idx + 1
        period_date = f"2024-{m:02d}-15"
        seasonal = SEASONAL[month_idx]
        base_rev = int(REVENUE_BASE[entity_id] * seasonal)

        # Add small random variation (±5%)
        variation = random.uniform(0.95, 1.05)
        revenue = int(base_rev * variation)
        cogs = int(revenue * 0.42)
        salaries = int(revenue * 0.25)
        rent = int(revenue * 0.04)
        depreciation = int(revenue * 0.03)
        marketing = int(revenue * random.uniform(0.02, 0.05))
        utilities = int(revenue * 0.015)
        travel = int(revenue * random.uniform(0.01, 0.025))

        journal_entries = [
            # (description, debit_acct, credit_acct, amount)
            ("Product revenue", "1100", "4010", revenue),
            ("Cost of goods sold", "5010", "1200", cogs),
            ("Monthly payroll", "6010", "1010", salaries),
            ("Office rent", "6020", "2010", rent),
            ("Depreciation", "6030", "1510", depreciation),
            ("Marketing spend", "6040", "1010", marketing),
            ("Utilities", "6060", "2010", utilities),
            ("Business travel", "6050", "1010", travel),
        ]

        # Collect cash from AR (slightly less than revenue to build AR)
        cash_collected = int(revenue * 0.92)
        journal_entries.append(("Cash collections", "1010", "1100", cash_collected))

        # Pay AP
        ap_paid = int((rent + utilities) * 0.85)
        journal_entries.append(("AP payments", "2010", "1010", ap_paid))

        for desc, dr_acct, cr_acct, amount in journal_entries:
            header_key += 1
            hk = header_key
            jnum = f"JE-{entity_id}-{m:02d}-{dr_acct}"

            gl_headers.append(
                f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, "
                f"{hk}, {val(period_date)}, 'Current', {val(jnum)}, "
                f"{val(period_date)}, '{jnum}', 'LedgerJournal', '{jnum}', "
                f"2024, {m}, {val(entity_id)})"
            )

            # FX conversion for reporting currency
            if accy == "CHF":
                fx = 1.0
            elif accy == "USD":
                fx = FX_CHF_USD[month_idx]
            else:
                fx = FX_CHF_EUR[month_idx]
            rpt_amt = round(amount * fx, 2)

            ledger_dr = f"{dr_acct}-{cc}-{dept}"
            ledger_cr = f"{cr_acct}-{cc}-{dept}"
            dj_dr = dim_json(dr_acct, cc, dept, bu)
            dj_cr = dim_json(cr_acct, cc, dept, bu)

            # Debit line
            line_key += 1
            gl_lines.append(
                f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, "
                f"{val(desc)}, 'No', {line_key}, 'Normal', "
                f"{val(ledger_dr)}, {val(period_date)}, {hk}, "
                f"{rpt_amt}, {val(accy)}, {amount}, {val(dj_dr)}, {amount})"
            )

            # Credit line
            line_key += 1
            gl_lines.append(
                f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, "
                f"{val(desc)}, 'Yes', {line_key}, 'Normal', "
                f"{val(ledger_cr)}, {val(period_date)}, {hk}, "
                f"{rpt_amt}, {val(accy)}, {amount}, {val(dj_cr)}, {amount})"
            )

    # Quarterly intercompany transactions (AMHQ charges management fees)
    if entity_id != "AMHQ":
        for q in [3, 6, 9, 12]:
            ic_amount = int(REVENUE_BASE[entity_id] * 0.02)
            ic_date = f"2024-{q:02d}-28"
            if accy == "USD":
                fx = FX_CHF_USD[q - 1]
            else:
                fx = FX_CHF_EUR[q - 1]
            rpt_amt = round(ic_amount * fx, 2)

            # Sub side: DR IC Expense, CR AP (IC payable)
            header_key += 1
            hk = header_key
            jnum = f"IC-{entity_id}-Q{q//3}"
            gl_headers.append(
                f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, "
                f"{hk}, {val(ic_date)}, 'Current', {val(jnum)}, "
                f"{val(ic_date)}, '{jnum}', 'LedgerJournal', '{jnum}', "
                f"2024, {q}, {val(entity_id)})"
            )
            line_key += 1
            gl_lines.append(
                f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, "
                f"'IC management fee', 'No', {line_key}, 'Normal', "
                f"'5030-{cc}-{dept}', {val(ic_date)}, {hk}, "
                f"{rpt_amt}, {val(accy)}, {ic_amount}, "
                f"{val(dim_json('5030', cc, dept, bu))}, {ic_amount})"
            )
            line_key += 1
            gl_lines.append(
                f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, "
                f"'IC management fee', 'Yes', {line_key}, 'Normal', "
                f"'2010-{cc}-{dept}', {val(ic_date)}, {hk}, "
                f"{rpt_amt}, {val(accy)}, {ic_amount}, "
                f"{val(dim_json('2010', cc, dept, bu))}, {ic_amount})"
            )

            # HQ side: DR AR (IC receivable), CR IC Revenue (in CHF)
            header_key += 1
            hk = header_key
            jnum = f"IC-AMHQ-from-{entity_id}-Q{q//3}"
            ic_chf = int(ic_amount * fx)
            gl_headers.append(
                f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, "
                f"{hk}, {val(ic_date)}, 'Current', {val(jnum)}, "
                f"{val(ic_date)}, '{jnum}', 'LedgerJournal', '{jnum}', "
                f"2024, {q}, 'AMHQ')"
            )
            hq_cc, hq_dept, hq_bu = "HQ", "MGMT", "CORP"
            line_key += 1
            gl_lines.append(
                f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, "
                f"'IC fee from {entity_id}', 'No', {line_key}, 'Normal', "
                f"'1100-{hq_cc}-{hq_dept}', {val(ic_date)}, {hk}, "
                f"{ic_chf}, 'CHF', {ic_chf}, "
                f"{val(dim_json('1100', hq_cc, hq_dept, hq_bu))}, {ic_chf})"
            )
            line_key += 1
            gl_lines.append(
                f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, "
                f"'IC fee from {entity_id}', 'Yes', {line_key}, 'Normal', "
                f"'4030-{hq_cc}-{hq_dept}', {val(ic_date)}, {hk}, "
                f"{ic_chf}, 'CHF', {ic_chf}, "
                f"{val(dim_json('4030', hq_cc, hq_dept, hq_bu))}, {ic_chf})"
            )

            # Settlement: Sub pays HQ (DR AP, CR Cash on sub / DR Cash, CR AR on HQ)
            # Settle in the following month (or same month for Q4)
            settle_m = min(q + 1, 12)
            settle_date = f"2024-{settle_m:02d}-15"

            # Use settlement month's FX rate (not original month's)
            if accy == "USD":
                settle_fx = FX_CHF_USD[settle_m - 1]
            else:
                settle_fx = FX_CHF_EUR[settle_m - 1]
            settle_rpt_amt = round(ic_amount * settle_fx, 2)
            settle_ic_chf = int(ic_amount * settle_fx)

            header_key += 1
            hk = header_key
            jnum = f"IC-SETTLE-{entity_id}-Q{q//3}"
            gl_headers.append(
                f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, "
                f"{hk}, {val(settle_date)}, 'Current', {val(jnum)}, "
                f"{val(settle_date)}, '{jnum}', 'LedgerJournal', '{jnum}', "
                f"2024, {settle_m}, {val(entity_id)})"
            )
            line_key += 1
            gl_lines.append(
                f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, "
                f"'IC settlement', 'No', {line_key}, 'Normal', "
                f"'2010-{cc}-{dept}', {val(settle_date)}, {hk}, "
                f"{settle_rpt_amt}, {val(accy)}, {ic_amount}, "
                f"{val(dim_json('2010', cc, dept, bu))}, {ic_amount})"
            )
            line_key += 1
            gl_lines.append(
                f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, "
                f"'IC settlement', 'Yes', {line_key}, 'Normal', "
                f"'1010-{cc}-{dept}', {val(settle_date)}, {hk}, "
                f"{settle_rpt_amt}, {val(accy)}, {ic_amount}, "
                f"{val(dim_json('1010', cc, dept, bu))}, {ic_amount})"
            )

            header_key += 1
            hk = header_key
            jnum = f"IC-SETTLE-AMHQ-from-{entity_id}-Q{q//3}"
            gl_headers.append(
                f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, "
                f"{hk}, {val(settle_date)}, 'Current', {val(jnum)}, "
                f"{val(settle_date)}, '{jnum}', 'LedgerJournal', '{jnum}', "
                f"2024, {settle_m}, 'AMHQ')"
            )
            line_key += 1
            gl_lines.append(
                f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, "
                f"'IC settlement from {entity_id}', 'No', {line_key}, 'Normal', "
                f"'1010-{hq_cc}-{hq_dept}', {val(settle_date)}, {hk}, "
                f"{settle_ic_chf}, 'CHF', {settle_ic_chf}, "
                f"{val(dim_json('1010', hq_cc, hq_dept, hq_bu))}, {settle_ic_chf})"
            )
            line_key += 1
            gl_lines.append(
                f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, "
                f"'IC settlement from {entity_id}', 'Yes', {line_key}, 'Normal', "
                f"'1100-{hq_cc}-{hq_dept}', {val(settle_date)}, {hk}, "
                f"{settle_ic_chf}, 'CHF', {settle_ic_chf}, "
                f"{val(dim_json('1100', hq_cc, hq_dept, hq_bu))}, {settle_ic_chf})"
            )

# ── Monthly IC product sales: AMUS → AMDE ────────────────────────
# AMUS sells components to AMDE at 15% markup
IC_MONTHLY_SALES = 120000  # USD base amount per month
for month_idx in range(12):
    m = month_idx + 1
    ic_date = f"2024-{m:02d}-20"
    seasonal = SEASONAL[month_idx]
    ic_sale = int(IC_MONTHLY_SALES * seasonal)
    # Convert USD sale to EUR for AMDE side
    usd_fx = FX_CHF_USD[month_idx]
    eur_fx = FX_CHF_EUR[month_idx]
    ic_sale_eur = int(ic_sale * usd_fx / eur_fx)  # USD → CHF → EUR
    ic_sale_chf = round(ic_sale * usd_fx, 2)

    # AMUS side: DR AR 1100 (IC receivable), CR IC Revenue 4030
    header_key += 1
    hk = header_key
    jnum = f"IC-SALE-AMUS-{m:02d}"
    gl_headers.append(
        f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, "
        f"{hk}, {val(ic_date)}, 'Current', {val(jnum)}, "
        f"{val(ic_date)}, '{jnum}', 'LedgerJournal', '{jnum}', "
        f"2024, {m}, 'AMUS')"
    )
    us_cc, us_dept, us_bu = "SALES", "SALES", "SERVICES"
    line_key += 1
    gl_lines.append(
        f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, "
        f"'IC product sale to AMDE', 'No', {line_key}, 'Normal', "
        f"'1100-{us_cc}-{us_dept}', {val(ic_date)}, {hk}, "
        f"{ic_sale_chf}, 'USD', {ic_sale}, "
        f"{val(dim_json('1100', us_cc, us_dept, us_bu))}, {ic_sale})"
    )
    line_key += 1
    gl_lines.append(
        f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, "
        f"'IC product sale to AMDE', 'Yes', {line_key}, 'Normal', "
        f"'4030-{us_cc}-{us_dept}', {val(ic_date)}, {hk}, "
        f"{ic_sale_chf}, 'USD', {ic_sale}, "
        f"{val(dim_json('4030', us_cc, us_dept, us_bu))}, {ic_sale})"
    )

    # AMDE side: DR IC Expense 5030, CR AP 2010 (IC payable)
    header_key += 1
    hk = header_key
    jnum = f"IC-PURCH-AMDE-{m:02d}"
    ic_sale_chf_de = round(ic_sale_eur * eur_fx, 2)
    gl_headers.append(
        f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, "
        f"{hk}, {val(ic_date)}, 'Current', {val(jnum)}, "
        f"{val(ic_date)}, '{jnum}', 'LedgerJournal', '{jnum}', "
        f"2024, {m}, 'AMDE')"
    )
    de_cc, de_dept, de_bu = "PROD", "OPS", "MANUFACTURING"
    line_key += 1
    gl_lines.append(
        f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, "
        f"'IC purchase from AMUS', 'No', {line_key}, 'Normal', "
        f"'5030-{de_cc}-{de_dept}', {val(ic_date)}, {hk}, "
        f"{ic_sale_chf_de}, 'EUR', {ic_sale_eur}, "
        f"{val(dim_json('5030', de_cc, de_dept, de_bu))}, {ic_sale_eur})"
    )
    line_key += 1
    gl_lines.append(
        f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, "
        f"'IC purchase from AMUS', 'Yes', {line_key}, 'Normal', "
        f"'2010-{de_cc}-{de_dept}', {val(ic_date)}, {hk}, "
        f"{ic_sale_chf_de}, 'EUR', {ic_sale_eur}, "
        f"{val(dim_json('2010', de_cc, de_dept, de_bu))}, {ic_sale_eur})"
    )

# Write GL headers
w("INSERT INTO epm_raw.general_journal_entry_bi_entities VALUES")
w(",\n".join(gl_headers) + ";")
w("")

# Write GL lines
w("INSERT INTO epm_raw.general_journal_account_entry_bi_entities VALUES")
w(",\n".join(gl_lines) + ";")

# ── Trial Balance Snapshots ───────────────────────────────────────
section("Trial Balance Snapshots (annual summary per account per entity)")

# We generate one snapshot row per account per entity
# with accumulated yearly totals
w("INSERT INTO epm_raw.trial_balance_fiscal_year_snapshots VALUES")
tb_rows = []
for entity_id, ename, country, accy, rcy, party in ENTITIES:
    for acct_id, acct_name, atype, cat, dc, chart in ACCOUNTS:
        # Opening balance from BS accounts
        opening = OPENING_BALANCES[entity_id].get(acct_id, 0)
        if opening < 0:
            opening = abs(opening)
            open_sign = -1
        else:
            open_sign = 1

        # Calculate yearly totals from our journal patterns
        total_debit = 0
        total_credit = 0
        base_rev = REVENUE_BASE[entity_id]

        for month_idx in range(12):
            seasonal = SEASONAL[month_idx]
            rev = int(base_rev * seasonal)

            if acct_id == "4010":
                total_credit += rev
            elif acct_id == "5010":
                total_debit += int(rev * 0.42)
            elif acct_id == "6010":
                total_debit += int(rev * 0.25)
            elif acct_id == "6020":
                total_debit += int(rev * 0.04)
            elif acct_id == "6030":
                total_debit += int(rev * 0.03)
            elif acct_id == "6040":
                total_debit += int(rev * 0.035)
            elif acct_id == "6060":
                total_debit += int(rev * 0.015)
            elif acct_id == "6050":
                total_debit += int(rev * 0.018)

        if total_debit == 0 and total_credit == 0 and opening == 0:
            continue

        ending = (opening * open_sign) + total_debit - total_credit

        tb_rows.append(
            f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, "
            f"'2024', {val(entity_id)}, {total_debit}, {total_credit}, "
            f"{ending}, {opening * open_sign}, {val(acct_id)}, '2024-01-01')"
        )

w(",\n".join(tb_rows) + ";")

# ── Budget Data ───────────────────────────────────────────────────
section("Budget Register Entries (FY2024 annual budget)")

w("INSERT INTO epm_raw.budget_register_entries VALUES")
budget_rows = []
entry_num = 0

for entity_id, ename, country, accy, rcy, party in ENTITIES:
    cc = COST_CENTERS[entity_id]
    dept = DEPARTMENTS[entity_id]
    bu = BIZ_UNITS[entity_id]
    base_rev = REVENUE_BASE[entity_id]

    # Budget: slightly higher revenue target, controlled expenses
    budget_items = [
        ("4010", -int(base_rev * 12 * 1.08 / 12)),   # Revenue target +8%
        ("5010", int(base_rev * 12 * 0.40 / 12)),     # COGS at 40%
        ("6010", int(base_rev * 12 * 0.24 / 12)),     # Salaries
        ("6020", int(base_rev * 12 * 0.04 / 12)),     # Rent
        ("6030", int(base_rev * 12 * 0.03 / 12)),     # Depreciation
        ("6040", int(base_rev * 12 * 0.03 / 12)),     # Marketing
        ("6050", int(base_rev * 12 * 0.015 / 12)),    # Travel
        ("6060", int(base_rev * 12 * 0.015 / 12)),    # Utilities
    ]

    for m in range(1, 13):
        for acct, amount in budget_items:
            entry_num += 1
            bdate = f"2024-{m:02d}-01"
            dim_display = f"{acct}-{cc}-{dept}"

            budget_rows.append(
                f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, "
                f"{val(bdate)}, 'Completed', 'Annual budget FY2024', "
                f"'Original', {val(dept)}, {val(entity_id)}, "
                f"'BUD-{entity_id}-{entry_num:04d}', {val(bu)}, {val(accy)}, "
                f"'FY2024', {val(entity_id)}, 'Annual budget', "
                f"{val(dim_display)}, {abs(amount)}, 'No', {abs(amount)})"
            )

w(",\n".join(budget_rows) + ";")

# ══════════════════════════════════════════════════════════════════
# ── epm_staging data (NCI ownership, IC elimination, IC balances) ─
# ══════════════════════════════════════════════════════════════════

section("epm_staging: Ownership Periods (PRD-11 — NCI for AMDE at 75%)")
w("INSERT INTO epm_staging.ownership_periods VALUES")
ownership_rows = []
for eid, ename, country, accy, rcy, party in ENTITIES:
    pct = 75.00 if eid == "AMDE" else 100.00
    method = "full"
    # All entities acquired at group inception (2020-01-01)
    ownership_rows.append(
        f"  ('AMG', {val(eid)}, '2020-01-01', '9999-12-31', {pct}, {val(method)}, "
        f"'2020-01-01', 1, 0, 0, '9999-12-31', 0, 0, now())"
    )
w(",\n".join(ownership_rows) + ";")

section("epm_staging: Consolidation Hierarchy")
w("INSERT INTO epm_staging.consolidation_hierarchy VALUES")
hier_rows = [
    # Group root
    "  ('AMG', '', '', 0, 100.00, 'AMG', now())",
    # Direct subsidiaries under AMG
    "  ('AMG', 'AMHQ', '', 1, 100.00, 'AMG/AMHQ', now())",
    "  ('AMG', 'AMUS', '', 1, 100.00, 'AMG/AMUS', now())",
    "  ('AMG', 'AMDE', '', 1, 75.00, 'AMG/AMDE', now())",
]
w(",\n".join(hier_rows) + ";")

section("epm_staging: IC Elimination Rules (enhanced with rule_type + margin)")
w("INSERT INTO epm_staging.ic_elimination_rules VALUES")
ic_rules = [
    # Balance-based: IC AR (1100) vs IC AP (2010)
    "  ('IC_AMG_001', 'IC AR/AP Elimination', '1100', '2010', '*', '*', "
    "'Eliminate IC receivables against IC payables', 'balance', 0, '', now())",
    # Balance-based: IC Revenue (4030) vs IC Expense (5030)
    "  ('IC_AMG_002', 'IC Revenue/Expense Elimination', '4030', '5030', '*', '*', "
    "'Eliminate IC product revenue against IC expense', 'balance', 0, '', now())",
    # Unrealized profit: AMUS sells to AMDE at 15% markup
    "  ('IC_AMG_003', 'IC Unrealized Profit in Inventory', '4030', '5030', 'AMUS', 'AMDE', "
    "'Eliminate unrealized profit on IC inventory (15% margin)', 'unrealized_profit', 15.00, '1200', now())",
]
w(",\n".join(ic_rules) + ";")

section("epm_staging: IC Balances (AMUS → AMDE monthly product sales)")
w("INSERT INTO epm_staging.ic_balances VALUES")
ic_bal_rows = []
for month_idx in range(12):
    m = month_idx + 1
    seasonal = SEASONAL[month_idx]
    ic_sale = int(IC_MONTHLY_SALES * seasonal)
    # 30% of IC purchases remain in ending inventory (AMDE hasn't sold them yet)
    ending_inv = int(ic_sale * 0.30)
    ic_bal_rows.append(
        f"  ('AMUS', 'AMDE', 2024, {m}, {ic_sale}, {ending_inv}, now())"
    )
w(",\n".join(ic_bal_rows) + ";")

# ══════════════════════════════════════════════════════════════════
# ╔════════════════════════════════════════════════════════════════╗
# ║  CONTOSO GROUP (GROUP_CORP) — additive second group, USD report ║
# ╚════════════════════════════════════════════════════════════════╝
#
# Everything above this line generates the Alpine Manufacturing Group
# (AMG) and is emitted byte-for-byte identically regardless of what
# follows. The Contoso block below only APPENDS new INSERT statements
# into the same epm_raw / epm_staging tables (ClickHouse permits many
# INSERTs per table), so AMG output is never perturbed. The global
# `random` stream continues deterministically (random.seed(42) above),
# keeping Contoso reproducible as well.
#
# Structure (USD reporting group):
#   GROUP_CORP (Contoso Group, USD)
#   ├── GROUP_EMEA (sub-group, USD)
#   │   ├── DEMF — Contoso DE (EUR functional) 100%
#   │   └── GBMF — Contoso UK (GBP functional)  80%  ← 20% NCI
#   ├── USMF — Contoso US (USD functional)      100%
#   └── JPMF — Contoso JP (JPY functional)      51%  ← 49% NCI
# ══════════════════════════════════════════════════════════════════

w("\n\n")
w("-- " + "#" * 70)
w("-- CONTOSO GROUP (GROUP_CORP) — second demo group, USD reporting")
w("-- 4 legal entities (USD, EUR, GBP, JPY), 12 months FY2024")
w("-- " + "#" * 70)

# ── Contoso company structure ─────────────────────────────────────
# (id, name, country, accounting_ccy, reporting_ccy, party_number)
CX_ENTITIES = [
    ("USMF", "Contoso US", "US", "USD", "USD", "CXP0001"),
    ("DEMF", "Contoso DE", "DE", "EUR", "USD", "CXP0002"),
    ("GBMF", "Contoso UK", "GB", "GBP", "USD", "CXP0003"),
    ("JPMF", "Contoso JP", "JP", "JPY", "USD", "CXP0004"),
]
CX_CHART = "GROUP_CORP"

# Cost centers / departments / business units per Contoso entity
CX_COST_CENTERS = {"USMF": "SALES", "DEMF": "PROD", "GBMF": "SALES", "JPMF": "PROD"}
CX_DEPARTMENTS = {"USMF": "SALES", "DEMF": "OPS", "GBMF": "SALES", "JPMF": "OPS"}
CX_BIZ_UNITS = {
    "USMF": "SERVICES", "DEMF": "MANUFACTURING",
    "GBMF": "SERVICES", "JPMF": "MANUFACTURING",
}

# Monthly revenue base (in each entity's functional currency)
CX_REVENUE_BASE = {"USMF": 900000, "DEMF": 650000, "GBMF": 500000, "JPMF": 90000000}

# FX rates: functional → USD (reporting), monthly for 2024.
# USD→USD is identity. Realistic 2024 levels.
CX_FX_USD_USD = [1.0000] * 12
CX_FX_EUR_USD = [1.0850, 1.0790, 1.0840, 1.0720, 1.0810, 1.0730,
                 1.0840, 1.0900, 1.1050, 1.0830, 1.0680, 1.0500]
CX_FX_GBP_USD = [1.2700, 1.2650, 1.2710, 1.2530, 1.2680, 1.2640,
                 1.2850, 1.2920, 1.3200, 1.3020, 1.2700, 1.2570]
CX_FX_JPY_USD = [0.006780, 0.006650, 0.006610, 0.006400, 0.006350, 0.006250,
                 0.006300, 0.006900, 0.007050, 0.006690, 0.006560, 0.006350]

CX_FX = {
    "USD": CX_FX_USD_USD,
    "EUR": CX_FX_EUR_USD,
    "GBP": CX_FX_GBP_USD,
    "JPY": CX_FX_JPY_USD,
}

# Acquisition-date (2020-01-01) historical FX → USD for IAS 21 equity
# translation. Equity is translated at the rate on the date the sub was
# acquired (group inception, 2020-01-01) — NOT the period/closing rate.
# Matches the ownership_periods effective_date of 2020-01-01. 2020 levels.
CX_ACQ_DATE = "2020-01-01"
CX_FX_ACQ_2020 = {"USD": 1.000000, "EUR": 1.121300, "GBP": 1.325700, "JPY": 0.009201}


def cx_fx(accy, month_idx):
    """Functional currency → USD reporting rate for given month index."""
    return CX_FX[accy][month_idx]


# ── Contoso Main Accounts (reuse AMG account numbers under GROUP_CORP)
section("Contoso: Main Accounts (chart GROUP_CORP)")
w("INSERT INTO epm_raw.main_accounts VALUES")
rows = []
for acct_id, name, atype, cat, dc, _chart in ACCOUNTS:
    rows.append(
        f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, "
        f"{val(name)}, 'No', {val(acct_id)}, {val(CX_CHART)}, "
        f"{val(atype)}, {val(dc)}, {val(cat)})"
    )
w(",\n".join(rows) + ";")

# ── Contoso Legal Entities ────────────────────────────────────────
section("Contoso: Legal Entities")
w("INSERT INTO epm_raw.legal_entities VALUES")
rows = []
for eid, ename, country, accy, rcy, party in CX_ENTITIES:
    rows.append(
        f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, "
        f"{val(ename)}, {val(eid)}, {val(country)}, {val(party)})"
    )
w(",\n".join(rows) + ";")

# ── Contoso Ledgers (functional ccy per entity, reporting USD) ────
section("Contoso: Ledgers (chart GROUP_CORP, reporting USD)")
w("INSERT INTO epm_raw.ledgers VALUES")
rows = []
for eid, ename, country, accy, rcy, party in CX_ENTITIES:
    rows.append(
        f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, "
        f"{val(ename + ' Ledger')}, {val(eid)}, {val(CX_CHART)}, {val(rcy)}, {val(accy)})"
    )
w(",\n".join(rows) + ";")

# ── Contoso Exchange Rates (EUR/GBP/JPY/USD → USD) ────────────────
section("Contoso: Exchange Rates (monthly EUR/GBP/JPY/USD → USD)")
w("INSERT INTO epm_raw.exchange_rates VALUES")
rows = []
cx_fx_count = 0
for month_idx in range(12):
    m = month_idx + 1
    start = f"2024-{m:02d}-01"
    end = "2024-12-31" if m == 12 else f"2024-{m+1:02d}-01"
    # ConversionFactor: JPY quoted per Hundred (Yen amounts large), others per One.
    # The D365 adapter (stg_d365_fo__exchange_rates) scales 'One'-factor rates
    # ×100 into the canonical ×100 store but passes 'Hundred'-factor rates
    # through unscaled, and silver_exchange_rates then divides everything by 100.
    # So a 'Hundred' rate must already be quoted per 100 units: store base×100
    # for JPY so the round-trip yields the true per-1 rate (1 JPY ≈ 0.0068 USD).
    for from_ccy, table in [("USD", CX_FX_USD_USD), ("EUR", CX_FX_EUR_USD),
                            ("GBP", CX_FX_GBP_USD), ("JPY", CX_FX_JPY_USD)]:
        base = table[month_idx]
        conv = "Hundred" if from_ccy == "JPY" else "One"
        store_scale = 100 if conv == "Hundred" else 1
        for rtype in ["Default", "Closing", "Average"]:
            r = round(base * store_scale, 9)
            if rtype == "Closing":
                r = round(base * store_scale * 1.005, 9)
            elif rtype == "Average":
                r = round(base * store_scale * 0.998, 9)
            rows.append(
                f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, "
                f"{r}, {val(end)}, {val(start)}, 'USD', {val(from_ccy)}, {val(rtype)}, {val(conv)})"
            )
            cx_fx_count += 1
# Acquisition-date (2020-01-01) historical rates for IAS 21 equity
# translation. One row per currency × rate type; point-in-time so the
# same value is used across Default/Closing/Average.
for from_ccy, acq_rate in CX_FX_ACQ_2020.items():
    conv = "Hundred" if from_ccy == "JPY" else "One"
    for rtype in ["Default", "Closing", "Average"]:
        rows.append(
            f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, "
            f"{acq_rate}, '2020-12-31', {val(CX_ACQ_DATE)}, 'USD', {val(from_ccy)}, {val(rtype)}, {val(conv)})"
        )
        cx_fx_count += 1
w(",\n".join(rows) + ";")

# ── Contoso Consolidation Account Group ───────────────────────────
section("Contoso: Consolidation Account Group")
w("INSERT INTO epm_raw.consolidate_account_groups VALUES")
w(f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, 'GROUP_CORP', 'Contoso Group');")

# ── Contoso GL Journal Entries ────────────────────────────────────
section("Contoso: GL Journal Entry Headers + Lines")

# Continue SourceKey ranges well clear of AMG's (AMG ~ <2000 headers / <20000 lines)
cx_header_key = 100000
cx_line_key = 1000000
cx_gl_headers = []
cx_gl_lines = []

# Opening balances per Contoso entity (functional currency).
# GBMF (80%) and JPMF (51%) carry healthy equity + retained earnings so
# NCI/minority interest is clearly visible post-consolidation.
CX_OPENING_BALANCES = {
    "USMF": {
        "1010": 3000000, "1100": 1400000, "1200": 1000000,
        "1500": 2400000, "1510": -500000,
        "2010": -700000, "2100": -350000, "2500": -1600000,
        "3010": -3000000, "3100": -1650000,  # RE balances the opening TB to zero
    },
    "DEMF": {
        "1010": 1700000, "1100": 950000, "1200": 1150000,
        "1500": 2600000, "1510": -520000,
        "2010": -450000, "2100": -260000, "2500": -1900000,
        "3010": -2700000, "3100": -570000,
    },
    "GBMF": {  # 80% owned — 20% NCI; sizeable equity + RE
        "1010": 1400000, "1100": 780000, "1200": 640000,
        "1500": 1900000, "1510": -360000,
        "2010": -380000, "2100": -210000, "2500": -1100000,
        "3010": -2000000, "3100": -670000,  # RE balances the opening TB to zero
    },
    "JPMF": {  # 51% owned — 49% NCI; amounts in JPY (large)
        "1010": 240000000, "1100": 130000000, "1200": 110000000,
        "1500": 300000000, "1510": -60000000,
        "2010": -70000000, "2100": -35000000, "2500": -180000000,
        "3010": -300000000, "3100": -135000000,
    },
}

for entity_id, ename, country, accy, rcy, party in CX_ENTITIES:
    cc = CX_COST_CENTERS[entity_id]
    dept = CX_DEPARTMENTS[entity_id]
    bu = CX_BIZ_UNITS[entity_id]

    # Opening balance journal (Jan 1)
    cx_header_key += 1
    hk = cx_header_key
    jnum = f"OB-{entity_id}-2024"
    adate = "2024-01-01"
    cx_gl_headers.append(
        f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, "
        f"{hk}, {val(adate)}, 'Current', {val(jnum)}, {val(adate)}, "
        f"'{jnum}', 'OpeningBalance', '{jnum}', 2024, 1, {val(entity_id)})"
    )
    for acct, bal in CX_OPENING_BALANCES[entity_id].items():
        cx_line_key += 1
        is_credit = "Yes" if bal < 0 else "No"
        amt = abs(bal)
        ledger_acct = f"{acct}-{cc}-{dept}"
        dj = dim_json(acct, cc, dept, bu)
        rpt_amt = round(amt * cx_fx(accy, 0), 2)
        cx_gl_lines.append(
            f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, "
            f"'Opening balance', {val(is_credit)}, {cx_line_key}, 'Normal', "
            f"{val(ledger_acct)}, {val(adate)}, {hk}, "
            f"{rpt_amt}, {val(accy)}, {amt}, {val(dj)}, {amt})"
        )

    # Monthly operational entries
    for month_idx in range(12):
        m = month_idx + 1
        period_date = f"2024-{m:02d}-15"
        seasonal = SEASONAL[month_idx]
        base_rev = int(CX_REVENUE_BASE[entity_id] * seasonal)
        variation = random.uniform(0.95, 1.05)
        revenue = int(base_rev * variation)
        cogs = int(revenue * 0.42)
        salaries = int(revenue * 0.25)
        rent = int(revenue * 0.04)
        depreciation = int(revenue * 0.03)
        marketing = int(revenue * random.uniform(0.02, 0.05))
        utilities = int(revenue * 0.015)
        travel = int(revenue * random.uniform(0.01, 0.025))

        journal_entries = [
            ("Product revenue", "1100", "4010", revenue),
            ("Cost of goods sold", "5010", "1200", cogs),
            ("Monthly payroll", "6010", "1010", salaries),
            ("Office rent", "6020", "2010", rent),
            ("Depreciation", "6030", "1510", depreciation),
            ("Marketing spend", "6040", "1010", marketing),
            ("Utilities", "6060", "2010", utilities),
            ("Business travel", "6050", "1010", travel),
        ]
        cash_collected = int(revenue * 0.92)
        journal_entries.append(("Cash collections", "1010", "1100", cash_collected))
        ap_paid = int((rent + utilities) * 0.85)
        journal_entries.append(("AP payments", "2010", "1010", ap_paid))

        fx = cx_fx(accy, month_idx)
        for desc, dr_acct, cr_acct, amount in journal_entries:
            cx_header_key += 1
            hk = cx_header_key
            jnum = f"JE-{entity_id}-{m:02d}-{dr_acct}"
            cx_gl_headers.append(
                f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, "
                f"{hk}, {val(period_date)}, 'Current', {val(jnum)}, "
                f"{val(period_date)}, '{jnum}', 'LedgerJournal', '{jnum}', "
                f"2024, {m}, {val(entity_id)})"
            )
            rpt_amt = round(amount * fx, 2)
            ledger_dr = f"{dr_acct}-{cc}-{dept}"
            ledger_cr = f"{cr_acct}-{cc}-{dept}"
            dj_dr = dim_json(dr_acct, cc, dept, bu)
            dj_cr = dim_json(cr_acct, cc, dept, bu)
            cx_line_key += 1
            cx_gl_lines.append(
                f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, "
                f"{val(desc)}, 'No', {cx_line_key}, 'Normal', "
                f"{val(ledger_dr)}, {val(period_date)}, {hk}, "
                f"{rpt_amt}, {val(accy)}, {amount}, {val(dj_dr)}, {amount})"
            )
            cx_line_key += 1
            cx_gl_lines.append(
                f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, "
                f"{val(desc)}, 'Yes', {cx_line_key}, 'Normal', "
                f"{val(ledger_cr)}, {val(period_date)}, {hk}, "
                f"{rpt_amt}, {val(accy)}, {amount}, {val(dj_cr)}, {amount})"
            )

# ── Contoso intercompany: USMF → DEMF monthly product sales ───────
# USMF sells components to DEMF at 15% markup (IC accounts 4030 / 5030),
# mirroring the AMG IC pattern. Both sides in their functional currency,
# reporting amounts in USD.
section("Contoso: Intercompany product sales (USMF -> DEMF)")
CX_IC_MONTHLY_SALES = 100000  # USD base per month
for month_idx in range(12):
    m = month_idx + 1
    ic_date = f"2024-{m:02d}-20"
    seasonal = SEASONAL[month_idx]
    ic_sale_usd = int(CX_IC_MONTHLY_SALES * seasonal)
    eur_fx = cx_fx("EUR", month_idx)         # EUR→USD
    ic_sale_eur = int(ic_sale_usd / eur_fx)  # USD → EUR for DEMF side
    ic_sale_usd_rpt = round(ic_sale_usd * 1.0, 2)  # USD reporting (identity)

    # USMF side: DR AR 1100 (IC receivable), CR IC Revenue 4030 (USD functional)
    cx_header_key += 1
    hk = cx_header_key
    jnum = f"IC-SALE-USMF-{m:02d}"
    cx_gl_headers.append(
        f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, "
        f"{hk}, {val(ic_date)}, 'Current', {val(jnum)}, "
        f"{val(ic_date)}, '{jnum}', 'LedgerJournal', '{jnum}', "
        f"2024, {m}, 'USMF')"
    )
    us_cc, us_dept, us_bu = "SALES", "SALES", "SERVICES"
    cx_line_key += 1
    cx_gl_lines.append(
        f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, "
        f"'IC product sale to DEMF', 'No', {cx_line_key}, 'Normal', "
        f"'1100-{us_cc}-{us_dept}', {val(ic_date)}, {hk}, "
        f"{ic_sale_usd_rpt}, 'USD', {ic_sale_usd}, "
        f"{val(dim_json('1100', us_cc, us_dept, us_bu))}, {ic_sale_usd})"
    )
    cx_line_key += 1
    cx_gl_lines.append(
        f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, "
        f"'IC product sale to DEMF', 'Yes', {cx_line_key}, 'Normal', "
        f"'4030-{us_cc}-{us_dept}', {val(ic_date)}, {hk}, "
        f"{ic_sale_usd_rpt}, 'USD', {ic_sale_usd}, "
        f"{val(dim_json('4030', us_cc, us_dept, us_bu))}, {ic_sale_usd})"
    )

    # DEMF side: DR IC Expense 5030, CR AP 2010 (IC payable) (EUR functional)
    cx_header_key += 1
    hk = cx_header_key
    jnum = f"IC-PURCH-DEMF-{m:02d}"
    ic_sale_eur_rpt = round(ic_sale_eur * eur_fx, 2)
    cx_gl_headers.append(
        f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, "
        f"{hk}, {val(ic_date)}, 'Current', {val(jnum)}, "
        f"{val(ic_date)}, '{jnum}', 'LedgerJournal', '{jnum}', "
        f"2024, {m}, 'DEMF')"
    )
    de_cc, de_dept, de_bu = "PROD", "OPS", "MANUFACTURING"
    cx_line_key += 1
    cx_gl_lines.append(
        f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, "
        f"'IC purchase from USMF', 'No', {cx_line_key}, 'Normal', "
        f"'5030-{de_cc}-{de_dept}', {val(ic_date)}, {hk}, "
        f"{ic_sale_eur_rpt}, 'EUR', {ic_sale_eur}, "
        f"{val(dim_json('5030', de_cc, de_dept, de_bu))}, {ic_sale_eur})"
    )
    cx_line_key += 1
    cx_gl_lines.append(
        f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, "
        f"'IC purchase from USMF', 'Yes', {cx_line_key}, 'Normal', "
        f"'2010-{de_cc}-{de_dept}', {val(ic_date)}, {hk}, "
        f"{ic_sale_eur_rpt}, 'EUR', {ic_sale_eur}, "
        f"{val(dim_json('2010', de_cc, de_dept, de_bu))}, {ic_sale_eur})"
    )

# Write Contoso GL headers + lines (separate INSERT statements)
w("INSERT INTO epm_raw.general_journal_entry_bi_entities VALUES")
w(",\n".join(cx_gl_headers) + ";")
w("")
w("INSERT INTO epm_raw.general_journal_account_entry_bi_entities VALUES")
w(",\n".join(cx_gl_lines) + ";")

# ── Contoso Trial Balance Snapshots ───────────────────────────────
section("Contoso: Trial Balance Snapshots (annual summary per account)")
w("INSERT INTO epm_raw.trial_balance_fiscal_year_snapshots VALUES")
cx_tb_rows = []
for entity_id, ename, country, accy, rcy, party in CX_ENTITIES:
    base_rev = CX_REVENUE_BASE[entity_id]
    for acct_id, acct_name, atype, cat, dc, _chart in ACCOUNTS:
        opening = CX_OPENING_BALANCES[entity_id].get(acct_id, 0)
        if opening < 0:
            opening = abs(opening)
            open_sign = -1
        else:
            open_sign = 1
        total_debit = 0
        total_credit = 0
        for month_idx in range(12):
            seasonal = SEASONAL[month_idx]
            rev = int(base_rev * seasonal)
            if acct_id == "4010":
                total_credit += rev
            elif acct_id == "5010":
                total_debit += int(rev * 0.42)
            elif acct_id == "6010":
                total_debit += int(rev * 0.25)
            elif acct_id == "6020":
                total_debit += int(rev * 0.04)
            elif acct_id == "6030":
                total_debit += int(rev * 0.03)
            elif acct_id == "6040":
                total_debit += int(rev * 0.035)
            elif acct_id == "6060":
                total_debit += int(rev * 0.015)
            elif acct_id == "6050":
                total_debit += int(rev * 0.018)
        if total_debit == 0 and total_credit == 0 and opening == 0:
            continue
        ending = (opening * open_sign) + total_debit - total_credit
        cx_tb_rows.append(
            f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, "
            f"'2024', {val(entity_id)}, {total_debit}, {total_credit}, "
            f"{ending}, {opening * open_sign}, {val(acct_id)}, '2024-01-01')"
        )
w(",\n".join(cx_tb_rows) + ";")

# ── Contoso Budget Register Entries ───────────────────────────────
section("Contoso: Budget Register Entries (FY2024 annual budget)")
w("INSERT INTO epm_raw.budget_register_entries VALUES")
cx_budget_rows = []
cx_entry_num = 0
for entity_id, ename, country, accy, rcy, party in CX_ENTITIES:
    cc = CX_COST_CENTERS[entity_id]
    dept = CX_DEPARTMENTS[entity_id]
    bu = CX_BIZ_UNITS[entity_id]
    base_rev = CX_REVENUE_BASE[entity_id]
    budget_items = [
        ("4010", -int(base_rev * 12 * 1.08 / 12)),
        ("5010", int(base_rev * 12 * 0.40 / 12)),
        ("6010", int(base_rev * 12 * 0.24 / 12)),
        ("6020", int(base_rev * 12 * 0.04 / 12)),
        ("6030", int(base_rev * 12 * 0.03 / 12)),
        ("6040", int(base_rev * 12 * 0.03 / 12)),
        ("6050", int(base_rev * 12 * 0.015 / 12)),
        ("6060", int(base_rev * 12 * 0.015 / 12)),
    ]
    for m in range(1, 13):
        for acct, amount in budget_items:
            cx_entry_num += 1
            bdate = f"2024-{m:02d}-01"
            dim_display = f"{acct}-{cc}-{dept}"
            cx_budget_rows.append(
                f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, "
                f"{val(bdate)}, 'Completed', 'Annual budget FY2024', "
                f"'Original', {val(dept)}, {val(entity_id)}, "
                f"'BUD-{entity_id}-{cx_entry_num:04d}', {val(bu)}, {val(accy)}, "
                f"'FY2024', {val(entity_id)}, 'Annual budget', "
                f"{val(dim_display)}, {abs(amount)}, 'No', {abs(amount)})"
            )
w(",\n".join(cx_budget_rows) + ";")

# ══════════════════════════════════════════════════════════════════
# ── Contoso epm_staging data (NCI ownership, hierarchy, IC) ───────
# ══════════════════════════════════════════════════════════════════

section("Contoso: Ownership Periods (NCI — GBMF 80%, JPMF 51%)")
w("INSERT INTO epm_staging.ownership_periods VALUES")
cx_ownership_rows = []
# Ownership is recorded against the consolidation group that directly
# owns the entity (GROUP_EMEA owns DEMF/GBMF; GROUP_CORP owns USMF/JPMF).
CX_OWNERSHIP = [
    ("GROUP_CORP", "USMF", 100.00),
    ("GROUP_EMEA", "DEMF", 100.00),
    ("GROUP_EMEA", "GBMF", 80.00),
    ("GROUP_CORP", "JPMF", 51.00),
]
for grp, eid, pct in CX_OWNERSHIP:
    cx_ownership_rows.append(
        f"  ({val(grp)}, {val(eid)}, '2020-01-01', '9999-12-31', {pct}, 'full', "
        f"'2020-01-01', 1, 0, 0, '9999-12-31', 0, 0, now())"
    )
w(",\n".join(cx_ownership_rows) + ";")

section("Contoso: Historical Equity Rates (IAS 21 — equity at acquisition FX)")
w("INSERT INTO epm_staging.historical_equity_rates VALUES")
# Equity accounts (Share Capital, Retained Earnings) translated at the
# 2020-01-01 acquisition-date rate (functional → USD), per IAS 21 — not the
# closing rate. Group matches direct owner (GROUP_EMEA: DEMF/GBMF).
CX_EQUITY_ACCOUNTS = ["3010", "3100"]
CX_HER = [
    ("GROUP_CORP", "USMF", "USD"),
    ("GROUP_EMEA", "DEMF", "EUR"),
    ("GROUP_EMEA", "GBMF", "GBP"),
    ("GROUP_CORP", "JPMF", "JPY"),
]
cx_her_rows = []
for grp, eid, accy in CX_HER:
    acq_rate = CX_FX_ACQ_2020[accy]
    for acct in CX_EQUITY_ACCOUNTS:
        cx_her_rows.append(
            f"  ({val(grp)}, {val(eid)}, {val(acct)}, {val(CX_ACQ_DATE)}, {acq_rate}, now())"
        )
w(",\n".join(cx_her_rows) + ";")

section("Contoso: Consolidation Hierarchy (GROUP_CORP / GROUP_EMEA)")
w("INSERT INTO epm_staging.consolidation_hierarchy VALUES")
cx_hier_rows = [
    # Roots / sub-group nodes (data_area_id empty)
    "  ('GROUP_CORP', '', '', 0, 100.00, 'GROUP_CORP', now())",
    "  ('GROUP_EMEA', '', 'GROUP_CORP', 1, 100.00, 'GROUP_CORP/GROUP_EMEA', now())",
    # Leaf entities
    "  ('GROUP_CORP', 'USMF', '', 1, 100.00, 'GROUP_CORP/USMF', now())",
    "  ('GROUP_CORP', 'JPMF', '', 1, 51.00, 'GROUP_CORP/JPMF', now())",
    "  ('GROUP_EMEA', 'DEMF', '', 2, 100.00, 'GROUP_CORP/GROUP_EMEA/DEMF', now())",
    "  ('GROUP_EMEA', 'GBMF', '', 2, 80.00, 'GROUP_CORP/GROUP_EMEA/GBMF', now())",
]
w(",\n".join(cx_hier_rows) + ";")

section("Contoso: IC Elimination Rules")
w("INSERT INTO epm_staging.ic_elimination_rules VALUES")
cx_ic_rules = [
    "  ('IC_CORP_001', 'IC AR/AP Elimination (Contoso)', '1100', '2010', '*', '*', "
    "'Eliminate IC receivables against IC payables', 'balance', 0, '', now())",
    "  ('IC_CORP_002', 'IC Revenue/Expense Elimination (Contoso)', '4030', '5030', '*', '*', "
    "'Eliminate IC product revenue against IC expense', 'balance', 0, '', now())",
    "  ('IC_CORP_003', 'IC Unrealized Profit (USMF->DEMF)', '4030', '5030', 'USMF', 'DEMF', "
    "'Eliminate unrealized profit on IC inventory (15% margin)', 'unrealized_profit', 15.00, '1200', now())",
]
w(",\n".join(cx_ic_rules) + ";")

section("Contoso: IC Balances (USMF -> DEMF monthly product sales)")
w("INSERT INTO epm_staging.ic_balances VALUES")
cx_ic_bal_rows = []
for month_idx in range(12):
    m = month_idx + 1
    seasonal = SEASONAL[month_idx]
    ic_sale = int(CX_IC_MONTHLY_SALES * seasonal)
    ending_inv = int(ic_sale * 0.30)
    cx_ic_bal_rows.append(
        f"  ('USMF', 'DEMF', 2024, {m}, {ic_sale}, {ending_inv}, now())"
    )
w(",\n".join(cx_ic_bal_rows) + ";")

# ── Contoso Fiscal Calendar ───────────────────────────────────────
# entity_fiscal_calendars maps the Contoso entities to the 'Fiscal'
# calendar, so its year boundaries must be loaded (silver_fiscal_periods
# expands them into 12 monthly periods). Without this, GL still works via
# the silver date-derivation fallback, but assert_fiscal_calendar_is_loaded
# fails. Appended last so no earlier UUIDs shift.
section("Contoso: Fiscal Calendar Years ('Fiscal')")
w("INSERT INTO epm_raw.fiscal_calendar_years VALUES")
w(f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, "
  f"'2024-12-31', 'Fiscal', '2024-01-01', '2024', 'Fiscal Year 2024');")

# ── Write output ──────────────────────────────────────────────────
output = "\n".join(lines) + "\n"
with open("clickhouse/demo-data.sql", "w") as f:
    f.write(output)

print(f"Generated clickhouse/demo-data.sql")
print(f"  [AMG] GL headers:  {len(gl_headers)}")
print(f"  [AMG] GL lines:    {len(gl_lines)}")
print(f"  [AMG] TB rows:     {len(tb_rows)}")
print(f"  [AMG] Budget rows: {len(budget_rows)}")
print(f"  [AMG] FX rates:    {12 * 6}")  # 12 months × 2 pairs × 3 types
print(f"  [AMG] Ownership:   {len(ownership_rows)}")
print(f"  [AMG] IC balances: {len(ic_bal_rows)}")
print(f"  [CORP] GL headers:  {len(cx_gl_headers)}")
print(f"  [CORP] GL lines:    {len(cx_gl_lines)}")
print(f"  [CORP] TB rows:     {len(cx_tb_rows)}")
print(f"  [CORP] Budget rows: {len(cx_budget_rows)}")
print(f"  [CORP] FX rates:    {cx_fx_count}")  # 12 months × 4 ccy × 3 types
print(f"  [CORP] Ownership:   {len(cx_ownership_rows)}")
print(f"  [CORP] Equity rates:{len(cx_her_rows)}")
print(f"  [CORP] IC balances: {len(cx_ic_bal_rows)}")
