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
    return str(uuid.uuid4())


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
    "MainAccounts": """
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

    "MainAccountCategories": """
    `_airbyte_raw_id` String,
    `_airbyte_extracted_at` DateTime64(3),
    `_airbyte_meta` String,
    `_airbyte_generation_id` UInt32,
    `Closed` Nullable(String),
    `Description` Nullable(String),
    `ReferenceId` Nullable(String),
    `MainAccountType` Nullable(String),
    `MainAccountCategory` Nullable(String)""",

    "LegalEntities": """
    `_airbyte_raw_id` String,
    `_airbyte_extracted_at` DateTime64(3),
    `_airbyte_meta` String,
    `_airbyte_generation_id` UInt32,
    `Name` Nullable(String),
    `LegalEntityId` Nullable(String),
    `AddressCountryRegionId` Nullable(String),
    `PartyNumber` Nullable(String)""",

    "Ledgers": """
    `_airbyte_raw_id` String,
    `_airbyte_extracted_at` DateTime64(3),
    `_airbyte_meta` String,
    `_airbyte_generation_id` UInt32,
    `Name` Nullable(String),
    `LegalEntityId` Nullable(String),
    `ChartOfAccountsId` Nullable(String),
    `ReportingCurrency` Nullable(String),
    `AccountingCurrency` Nullable(String)""",

    "FiscalCalendarYears": """
    `_airbyte_raw_id` String,
    `_airbyte_extracted_at` DateTime64(3),
    `_airbyte_meta` String,
    `_airbyte_generation_id` UInt32,
    `EndDate` Nullable(String),
    `Calendar` Nullable(String),
    `StartDate` Nullable(String),
    `FiscalYear` Nullable(String),
    `Description` Nullable(String)""",

    "ExchangeRates": """
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

    "ExchangeRateTypes": """
    `_airbyte_raw_id` String,
    `_airbyte_extracted_at` DateTime64(3),
    `_airbyte_meta` String,
    `_airbyte_generation_id` UInt32,
    `Name` Nullable(String),
    `Description` Nullable(String)""",

    "DimensionAttributes": """
    `_airbyte_raw_id` String,
    `_airbyte_extracted_at` DateTime64(3),
    `_airbyte_meta` String,
    `_airbyte_generation_id` UInt32,
    `DimensionName` Nullable(String),
    `UseValuesFrom` Nullable(String),
    `ReportColumnName` Nullable(String)""",

    "FinancialDimensionValues": """
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

    "ConsolidateAccountGroups": """
    `_airbyte_raw_id` String,
    `_airbyte_extracted_at` DateTime64(3),
    `_airbyte_meta` String,
    `_airbyte_generation_id` UInt32,
    `ConsolidationAccountGroup` Nullable(String),
    `ConsolidationAccountGroupName` Nullable(String)""",

    "GeneralJournalEntryBiEntities": """
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

    "GeneralJournalAccountEntryBiEntities": """
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

    "BudgetRegisterEntries": """
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

    "TrialBalanceFiscalYearSnapshots": """
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
w("INSERT INTO epm_raw.MainAccounts VALUES")
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
w("INSERT INTO epm_raw.MainAccountCategories VALUES")
rows = []
for ref_id, cat, desc, atype in CATEGORIES:
    rows.append(
        f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, "
        f"'No', {val(desc)}, {val(ref_id)}, {val(atype)}, {val(cat)})"
    )
w(",\n".join(rows) + ";")

# ── Legal Entities ────────────────────────────────────────────────
section("Legal Entities")
w("INSERT INTO epm_raw.LegalEntities VALUES")
rows = []
for eid, ename, country, accy, rcy, party in ENTITIES:
    rows.append(
        f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, "
        f"{val(ename)}, {val(eid)}, {val(country)}, {val(party)})"
    )
w(",\n".join(rows) + ";")

# ── Ledgers ───────────────────────────────────────────────────────
section("Ledgers")
w("INSERT INTO epm_raw.Ledgers VALUES")
rows = []
for eid, ename, country, accy, rcy, party in ENTITIES:
    rows.append(
        f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, "
        f"{val(ename + ' Ledger')}, {val(eid)}, 'AMG', {val(rcy)}, {val(accy)})"
    )
w(",\n".join(rows) + ";")

# ── Fiscal Calendar ───────────────────────────────────────────────
section("Fiscal Calendar Years")
w("INSERT INTO epm_raw.FiscalCalendarYears VALUES")
w(f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, "
  f"'2024-12-31', 'Standard', '2024-01-01', '2024', 'Fiscal Year 2024');")

# ── Exchange Rate Types ───────────────────────────────────────────
section("Exchange Rate Types")
w("INSERT INTO epm_raw.ExchangeRateTypes VALUES")
w(f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, 'Default', 'Default exchange rate'),")
w(f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, 'Closing', 'Month-end closing rate'),")
w(f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, 'Average', 'Monthly average rate');")

# ── Exchange Rates ────────────────────────────────────────────────
section("Exchange Rates (Monthly CHF/USD and CHF/EUR)")
w("INSERT INTO epm_raw.ExchangeRates VALUES")
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
w("INSERT INTO epm_raw.DimensionAttributes VALUES")
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
w("INSERT INTO epm_raw.FinancialDimensionValues VALUES")
rows = []
for dim, dval, desc in DIM_VALUES:
    rows.append(
        f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, "
        f"'2099-12-31', '2024-01-01', {val(desc)}, 'No', {val(dval)}, {val(dim)})"
    )
w(",\n".join(rows) + ";")

# ── Consolidation Account Groups ──────────────────────────────────
section("Consolidation Account Groups")
w("INSERT INTO epm_raw.ConsolidateAccountGroups VALUES")
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
                f"{rpt_amt}, {val(accy)}, {ic_amount}, "
                f"{val(dim_json('2010', cc, dept, bu))}, {ic_amount})"
            )
            line_key += 1
            gl_lines.append(
                f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, "
                f"'IC settlement', 'Yes', {line_key}, 'Normal', "
                f"'1010-{cc}-{dept}', {val(settle_date)}, {hk}, "
                f"{rpt_amt}, {val(accy)}, {ic_amount}, "
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
                f"{ic_chf}, 'CHF', {ic_chf}, "
                f"{val(dim_json('1010', hq_cc, hq_dept, hq_bu))}, {ic_chf})"
            )
            line_key += 1
            gl_lines.append(
                f"  ({val(uid())}, '{NOW}', '{META}', {GEN}, "
                f"'IC settlement from {entity_id}', 'Yes', {line_key}, 'Normal', "
                f"'1100-{hq_cc}-{hq_dept}', {val(settle_date)}, {hk}, "
                f"{ic_chf}, 'CHF', {ic_chf}, "
                f"{val(dim_json('1100', hq_cc, hq_dept, hq_bu))}, {ic_chf})"
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
w("INSERT INTO epm_raw.GeneralJournalEntryBiEntities VALUES")
w(",\n".join(gl_headers) + ";")
w("")

# Write GL lines
w("INSERT INTO epm_raw.GeneralJournalAccountEntryBiEntities VALUES")
w(",\n".join(gl_lines) + ";")

# ── Trial Balance Snapshots ───────────────────────────────────────
section("Trial Balance Snapshots (annual summary per account per entity)")

# We generate one snapshot row per account per entity
# with accumulated yearly totals
w("INSERT INTO epm_raw.TrialBalanceFiscalYearSnapshots VALUES")
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

w("INSERT INTO epm_raw.BudgetRegisterEntries VALUES")
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

# ── Write output ──────────────────────────────────────────────────
output = "\n".join(lines) + "\n"
with open("clickhouse/demo-data.sql", "w") as f:
    f.write(output)

print(f"Generated clickhouse/demo-data.sql")
print(f"  GL headers:  {len(gl_headers)}")
print(f"  GL lines:    {len(gl_lines)}")
print(f"  TB rows:     {len(tb_rows)}")
print(f"  Budget rows: {len(budget_rows)}")
print(f"  FX rates:    {12 * 6}")  # 12 months × 2 pairs × 3 types
print(f"  Ownership:   {len(ownership_rows)}")
print(f"  IC balances: {len(ic_bal_rows)}")
