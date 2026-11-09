#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = ["openpyxl>=3.1"]
# ///
"""Build the Mini Group onboarding example.

    uv run build_mini.py

The smallest consolidation that still has a story: one holding company with
two companies held throughout, one bought, one sold. No financial dimensions, no currencies other than
EUR, no intercompany. Three periods only — Start, Activity, Close.

Numbers are whole euros and are written out in examples/mini/README.md.
"""
from __future__ import annotations

import os
import sys
from decimal import Decimal

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from konsol_template import SHEETS, TB_HEADER, write_workbook  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
EXAMPLE_DIR = os.path.join(HERE, "examples", "mini")

GROUP = "MINI"
CURRENCY = "EUR"
CHART = "MINI_GROUP"
BASIS = "Period-end balance"
FY = 2025

# Activity is 1 Feb–31 Dec: konsol requires the last Regular period to end on
# the year end, and the Closing period is that same single day (31 Dec). The
# acquisition (1 Feb, the period's first day) and the disposal (30 Dec, inside
# it) both land in Activity; ownership ends on 30 Dec, so the company sold is
# out of the group when the books close on 31 Dec.
ACQ_DATE = "2025-02-01"
DSP_DATE = "2025-12-30"
CONSIDERATION = 1_200_000
ACQ_COSTS = 50_000
FVA = 100_000          # step-up on the acquired company's plant
PROCEEDS = 1_000_000

# (code, name, parent, account_type, sub_section, flags, cf)
# flags: G heading, C cash, RE retained earnings, hist historical rate, cr contra
A = []


def acct(code, name, parent, atype, sub, flags="", cf=None):
    A.append((code, name, parent, atype, sub, flags, cf))


acct("1000", "Assets", "", "Asset", "", "G")
acct("1100", "Cash", "1000", "Asset", "Current assets", "C", ("Operating", "Cash and cash equivalents"))
acct("1200", "Property, plant and equipment", "1000", "Asset", "Non-current assets", "", ("Investing", "Purchase of property, plant and equipment"))
acct("1210", "Accumulated depreciation", "1000", "Asset", "Non-current assets", "cr", ("Operating", "Depreciation"))
acct("1300", "Investments in subsidiaries", "1000", "Asset", "Non-current assets", "", ("Investing", "Investments in subsidiaries"))
acct("1400", "Goodwill", "1000", "Asset", "Non-current assets", "", ("Investing", "Acquisitions of businesses"))
acct("1410", "Fair value adjustments on acquisition", "1000", "Asset", "Non-current assets", "", ("Investing", "Acquisitions of businesses"))
acct("1500", "Deal settlement account", "1000", "Asset", "Current assets", "", ("Investing", "Acquisitions and disposals of businesses"))
acct("1600", "Trade receivables", "1000", "Asset", "Current assets", "", ("Operating", "Change in trade receivables"))
acct("2000", "Liabilities", "", "Liability", "", "G")
acct("2100", "Trade payables", "2000", "Liability", "Current liabilities", "", ("Operating", "Change in trade payables"))
acct("3000", "Equity", "", "Equity", "Equity", "G")
acct("3100", "Share capital", "3000", "Equity", "Equity", "hist", ("Financing", "Share capital"))
acct("3300", "Retained earnings", "3000", "Equity", "Equity", "RE", ("Operating", "Net income"))
acct("3700", "Non-controlling interests", "3000", "Equity", "Equity", "", ("Financing", "Non-controlling interests"))
acct("4000", "Profit and loss", "", "Revenue", "", "G")
acct("4100", "Revenue", "4000", "Revenue", "Revenue")
acct("5100", "Cost of sales", "4000", "Expense", "Cost of sales")
acct("6100", "Operating expenses", "4000", "Expense", "Operating expenses")
acct("6600", "Depreciation", "4000", "Expense", "Operating expenses")
acct("6640", "Amortisation of goodwill", "4000", "Expense", "Operating expenses")
acct("6730", "Gain or loss on disposal", "4000", "Expense", "Operating expenses")
acct("6750", "Intercompany differences", "4000", "Expense", "Operating expenses")
acct("6760", "Bargain purchase gain", "4000", "Expense", "Operating expenses", "cr")
acct("6770", "Acquisition-related costs", "4000", "Expense", "Operating expenses")
acct("8100", "Income tax expense", "4000", "Expense", "Income taxes")

ACCOUNT_NAME = {c: n for c, n, *_ in A}

# Signed euros, debit positive. Each block sums to zero.
# Start has balance sheets only. Activity still has the year's result in the
# P&L. Close has moved that result into retained earnings.
BOOKS = {
    "HOLD": {
        "START": {1100: 1_700_000, 1300: 800_000, 3100: -1_500_000, 3300: -1_000_000},
        "ACT": {1100: 1_370_000, 1300: 2_000_000, 1500: -950_000, 3100: -1_500_000, 3300: -1_000_000, 6100: 80_000},
        "CLS": {1100: 1_370_000, 1300: 2_000_000, 1500: -950_000, 3100: -1_500_000, 3300: -920_000},
    },
    "DSP": {
        "START": {1100: 200_000, 1200: 800_000, 1210: -200_000, 1600: 100_000, 2100: -150_000, 3100: -500_000, 3300: -250_000},
        "ACT": {1100: 320_000, 1200: 800_000, 1210: -230_000, 1600: 100_000, 2100: -150_000,
                3100: -500_000, 3300: -250_000, 4100: -400_000, 5100: 180_000, 6100: 70_000, 6600: 30_000, 8100: 30_000},
        "CLS": {1100: 320_000, 1200: 800_000, 1210: -230_000, 1600: 100_000, 2100: -150_000, 3100: -500_000, 3300: -340_000},
    },
    "SVC": {
        "START": {1100: 300_000, 1600: 100_000, 2100: -120_000, 3100: -100_000, 3300: -180_000},
        "ACT": {1100: 360_000, 1600: 100_000, 2100: -120_000, 3100: -100_000, 3300: -180_000,
                4100: -300_000, 5100: 120_000, 6100: 90_000, 8100: 30_000},
        "CLS": {1100: 360_000, 1600: 100_000, 2100: -120_000, 3100: -100_000, 3300: -240_000},
    },
    "PRT": {
        "START": {1100: 150_000, 1200: 400_000, 1210: -100_000, 1600: 60_000, 2100: -90_000, 3100: -200_000, 3300: -220_000},
        "ACT": {1100: 210_000, 1200: 400_000, 1210: -120_000, 1600: 60_000, 2100: -90_000,
                3100: -200_000, 3300: -220_000, 4100: -220_000, 5100: 100_000, 6100: 40_000, 6600: 20_000, 8100: 20_000},
        "CLS": {1100: 210_000, 1200: 400_000, 1210: -120_000, 1600: 60_000, 2100: -90_000, 3100: -200_000, 3300: -260_000},
    },
    "ACQ": {
        "START": {1100: 300_000, 1200: 700_000, 1210: -100_000, 1600: 80_000, 2100: -80_000, 3100: -400_000, 3300: -500_000},
        "ACT": {1100: 390_000, 1200: 700_000, 1210: -120_000, 1600: 80_000, 2100: -80_000,
                3100: -400_000, 3300: -500_000, 4100: -250_000, 5100: 100_000, 6100: 40_000, 6600: 20_000, 8100: 20_000},
        "CLS": {1100: 390_000, 1200: 700_000, 1210: -120_000, 1600: 80_000, 2100: -80_000, 3100: -400_000, 3300: -570_000},
    },
}

ENTITIES = {
    "HOLD": ("Mini Holding AG", "NL", "Active"),
    "SVC": ("Mini Services B.V.", "NL", "Active"),
    "PRT": ("Mini Parts GmbH", "DE", "Active"),
    "DSP": ("Mini Disposed GmbH", "DE", "Disposed"),
    "ACQ": ("Mini Acquired GmbH", "DE", "Active"),
}

# Which entities have a file in each period. All five do: ACQ's Start file is
# the balance sheet the acquisition reads, and DSP's Close file is its own
# books after the sale (the group no longer owns it).
PERIODS = (
    ("START", 1, "Regular", "Q1", "2025-01-01", "2025-01-31", "Start", ("HOLD", "SVC", "PRT", "DSP", "ACQ")),
    ("ACT", 2, "Regular", "", "2025-02-01", "2025-12-31", "Activity", ("HOLD", "SVC", "PRT", "DSP", "ACQ")),
    ("CLS", 13, "Closing", "", "2025-12-31", "2025-12-31", "Close", ("HOLD", "SVC", "PRT", "DSP", "ACQ")),
)
PERIOD_NO = {code: n for code, n, *_ in PERIODS}

POLICY = {
    "accounting_framework": "IFRS", "goodwill_method": "partial", "goodwill_treatment": "Impairment only",
    "acquisition_costs_treatment": "Expense", "measurement_period": "12 months", "bargain_purchase": "Recognise gain",
    "goodwill_account": "1400", "fair_value_adjustment_account": "1410", "investment_account": "1300",
    "nci_account": "3700", "bargain_purchase_gain_account": "6760", "disposal_gain_loss_account": "6730",
    "disposal_proceeds_account": "1500", "goodwill_amortisation_expense_account": "6640",
    "acquisition_costs_account": "6770", "ic_difference_account": "6750", "ic_difference_tolerance": 0,
}


def chart_rows():
    rows = []
    for code, name, parent, atype, sub, flags, cf in A:
        f = set(flags.split()) if flags else set()
        heading = "G" in f
        section = "" if not atype else ("Balance Sheet" if atype in ("Asset", "Liability", "Equity") else "Profit and Loss")
        if code == "4000":
            section = "Profit and Loss"
        row = {"main_account": code, "account_name": name, "chart_of_accounts": CHART, "parent_account": parent,
               "is_group": 1 if heading else 0, "account_type": atype, "statement_section": section, "sub_section": sub,
               "status": "Published", "is_posting": 0 if heading else 1}
        if not heading:
            row["normal_balance"] = "Debit" if atype in ("Asset", "Expense") else "Credit"
            if "cr" in f:
                row["normal_balance"] = "Credit"
            row["time_balance"] = "balance" if section == "Balance Sheet" else "flow"
            row["fx_method"] = "historical" if "hist" in f else ("closing" if section == "Balance Sheet" else "average")
            row["allow_ic"] = 0
            row["is_cash"] = 1 if "C" in f else 0
            row["is_retained_earnings"] = 1 if "RE" in f else 0
            if cf and section == "Balance Sheet":
                row["cf_category"], row["cf_line_item"] = cf
        rows.append(row)
    return rows


def check_books():
    for entity, periods in BOOKS.items():
        for period, rows in periods.items():
            total = sum(rows.values())
            assert total == 0, "%s %s does not balance: %s" % (entity, period, total)


def tb_rows(entity, period):
    out = []
    for account in sorted(BOOKS[entity][period]):
        cents = BOOKS[entity][period][account]
        if cents == 0:
            continue
        debit, credit = (cents, 0) if cents > 0 else (0, -cents)
        out.append({"data_area_id": entity, "fiscal_year": FY, "fiscal_period": PERIOD_NO[period],
                    "main_account": str(account), "debit": debit, "credit": credit, "currency": CURRENCY,
                    "description": ACCOUNT_NAME[str(account)], "partner_data_area_id": "", "amount_basis": BASIS})
    return out


def acquired_balance_rows():
    """ACQ at Start: the last period-end before the acquisition. Already a balance sheet."""
    rows = []
    for account in sorted(BOOKS["ACQ"]["START"]):
        amount = BOOKS["ACQ"]["START"][account]
        if amount == 0:
            continue
        rows.append({"deal_ref": "ACQ-ACQ-2025", "main_account": str(account), "book_amount": amount,
                     "fair_value_adjustment": FVA if account == 1200 else "",
                     "note": "Balance at 31 January 2025, the Start period"})
    assert sum(BOOKS["ACQ"]["START"].values()) == 0
    return rows


def master_rows(sample):
    years = [{"fiscal_year": FY, "start_date": "2025-01-01", "end_date": "2025-12-31",
              "period_pattern": "Custom", "include_opening_period": 0, "include_closing_period": 1}]
    periods = [{"fiscal_year": FY, "fiscal_period": n, "period_code": code, "period_label": label,
                "period_type": kind, "quarter": quarter, "start_date": start, "end_date": end}
               for code, n, kind, quarter, start, end, label, _entities in PERIODS]
    entities = [{"entity_code": code, "entity_name": name, "parent_entity": "", "is_group": 0, "status": status,
                 "reporting_frequency": "", "functional_currency": CURRENCY, "country": country, "erp_source": "tb_upload"}
                for code, (name, country, status) in ENTITIES.items()]
    groups = [{"consolidation_group": GROUP, "data_area_id": "", "entity_name": "Mini Group (consolidated)",
               "parent_group": "", "is_group": 1, "reporting_currency": CURRENCY, **POLICY}]
    for code, (name, _country, _status) in ENTITIES.items():
        groups.append({"consolidation_group": GROUP, "data_area_id": code, "entity_name": name,
                       "parent_group": GROUP, "is_group": 0})
    # ACQ's ownership is created when the Business Combination is approved.
    # HOLD is held by the group root (blank owner = its tree parent, MINI); the companies it holds name it.
    ownership = [
        {"consolidation_group": GROUP, "data_area_id": code, "effective_date": "2020-01-01", "end_date": "",
         "ownership_pct": 100, "consolidation_method": "full", "owner_entity": "" if code == "HOLD" else "HOLD"}
        for code in ("HOLD", "DSP", "SVC", "PRT")
    ]
    journal = [{"journal_ref": "CJ-OPEN-2025", "consolidation_group": GROUP, "adjustment_type": "topside",
                "fiscal_year": FY, "fiscal_period": PERIOD_NO["START"], "currency": CURRENCY,
                "description": "Opening consolidation: HOLD's investments in DSP, SVC and PRT eliminated against their share capital",
                "reverse_fiscal_year": "", "reverse_fiscal_period": ""}]
    journal_lines = []
    for code in ("DSP", "SVC", "PRT"):
        cost = -BOOKS[code]["START"][3100]
        journal_lines += [
            {"journal_ref": "CJ-OPEN-2025", "data_area_id": code, "main_account": "3100",
             "debit_amount": cost, "credit_amount": "", "description": "%s share capital" % code},
            {"journal_ref": "CJ-OPEN-2025", "data_area_id": "HOLD", "main_account": "1300",
             "debit_amount": "", "credit_amount": cost, "description": "HOLD cost of %s" % code},
        ]
    rows = {
        "Settings": [{"setting": "default_amount_basis", "value": BASIS},
                     {"setting": "tb_accepts_opening", "value": "0"},
                     {"setting": "tb_accepts_closing", "value": "1"},
                     {"setting": "tb_accepts_adjustment", "value": "0"},
                     {"setting": "self_approval", "value": "Allowed with reason"}],
        "Fiscal_Years": years, "Fiscal_Periods": periods, "Entities": entities,
        "Dimensions": [], "Reporting_Hierarchies": [], "Reporting_Hierarchy_Members": [], "Dimension_Mappings": [],
        "Main_Accounts": chart_rows(), "Intercompany_Accounts": [], "IC_Elimination_Rules": [],
        "Scenarios": [{"scenario_id": "ACTUAL", "scenario_name": "Actual", "scenario_type": "actual", "is_active": 1}],
        "Consolidation_Groups": groups, "Ownership_Periods": ownership,
        "FX_Rates": [], "Historical_Equity_Rates": [],
        "Consolidation_Journals": journal, "CJ_Lines": journal_lines,
        "Business_Combinations": [{
            "deal_ref": "ACQ-ACQ-2025", "consolidation_group": GROUP, "acquired_entity": "ACQ",
            "acquirer_entity": "HOLD", "acquisition_date": ACQ_DATE, "share_acquired_pct": 100, "consideration_currency": CURRENCY,
            "nci_measurement_override": "", "nci_fair_value": "", "fair_value_adjustment_total": FVA,
            "description": "100% of Mini Acquired GmbH bought for cash on the first day of Activity; plant stepped up"}],
        "BC_Consideration": [{"deal_ref": "ACQ-ACQ-2025", "component": "Cash", "amount": CONSIDERATION,
                              "currency": CURRENCY, "settlement_date": ACQ_DATE, "description": "Paid on completion"}],
        "BC_Acquired_Balances": acquired_balance_rows(),
        "BC_Costs": [{"deal_ref": "ACQ-ACQ-2025", "kind": "Legal", "amount": ACQ_COSTS, "currency": CURRENCY,
                      "description": "Legal fees, expensed"}],
        "Business_Disposals": [{
            "deal_ref": "DSP-DSP-2025", "consolidation_group": GROUP, "disposed_entity": "DSP", "disposer_entity": "HOLD",
            "disposal_date": DSP_DATE, "share_disposed_pct": 100, "retained_interest_pct": 0,
            "proceeds_currency": CURRENCY,
            "description": "100% of Mini Disposed GmbH sold for cash on the last day of Activity"}],
        "BD_Proceeds": [{"deal_ref": "DSP-DSP-2025", "component": "Cash", "amount": PROCEEDS, "currency": CURRENCY,
                         "settlement_date": DSP_DATE, "description": "Received on completion"}],
        "Trial_Balance": sample,
    }
    known = {s.name for s in SHEETS}
    missing = [k for k in rows if k not in known]
    assert not missing, missing
    return rows


def write_tb_file(path, rows, label):
    from openpyxl import Workbook
    from openpyxl.styles import Font, PatternFill
    wb = Workbook()
    ws = wb.active
    ws.title = "trial_balance"
    ws.append(list(TB_HEADER))
    for c in ws[1]:
        c.font = Font(name="Arial", bold=True, color="FFFFFF", size=10)
        c.fill = PatternFill("solid", fgColor="1F3864")
    for r in rows:
        ws.append([r["data_area_id"], r["fiscal_year"], r["fiscal_period"], r["main_account"],
                   Decimal(r["debit"]) if r["debit"] else None,
                   Decimal(r["credit"]) if r["credit"] else None,
                   r["currency"], r["description"], None, r["amount_basis"]])
    for col, w in {"A": 14, "B": 12, "C": 14, "D": 14, "E": 16, "F": 16, "G": 10, "H": 42, "I": 20, "J": 20}.items():
        ws.column_dimensions[col].width = w
    for row in ws.iter_rows(min_row=2, min_col=5, max_col=6):
        for c in row:
            c.number_format = "#,##0.00"
    ws.freeze_panes = "A2"
    ws.auto_filter.ref = ws.dimensions
    about = wb.create_sheet("About")
    entities = []
    for r in rows:
        if r["data_area_id"] not in entities:
            entities.append(r["data_area_id"])
    for line in (
        "Mini Group example — bulk trial balance for %s (%s)." % (label, BASIS),
        "No dimension columns. One currency (EUR). No intercompany partner.",
        "%d rows, entities %s. Debits equal credits per entity." % (len(rows), ", ".join(entities)),
        "Generated by excel/onboarding/build_mini.py. See examples/mini/README.md.",
    ):
        about.append([line])
    about.column_dimensions["A"].width = 120
    wb.save(path)


def build():
    check_books()
    os.makedirs(os.path.join(EXAMPLE_DIR, "tb"), exist_ok=True)
    files = {}
    for code, _n, _kind, _q, _s, _e, label, entities in PERIODS:
        rows = []
        for entity in entities:
            rows.extend(tb_rows(entity, code))
        files[code] = rows
        path = os.path.join(EXAMPLE_DIR, "tb", "TB_FY2025_P%02d_%s.xlsx" % (PERIOD_NO[code], code))
        write_tb_file(path, rows, label)
        print("wrote %s (%d rows)" % (os.path.relpath(path, HERE), len(rows)))
    sample = tb_rows("HOLD", "ACT")
    rows = master_rows(sample)
    path = os.path.join(EXAMPLE_DIR, "Mini_Master_Data.xlsx")
    intro = (
        "Filled onboarding workbook for the Mini Group: five legal entities, all in EUR, no financial dimensions, "
        "no intercompany. A flat consolidation tree under MINI. HOLD holds SVC, PRT and DSP throughout and acquires ACQ; one acquisition and one disposal, both by HOLD.",
        "Three periods only, on a Custom calendar: Start (FY2025 P01, opening balance sheets), Activity (P02, the year's "
        "trading, the acquisition on its first day and the disposal on its last day), Close (P13, the result moved into "
        "retained earnings). Trial balances are in tb/.",
        "Consolidation_Journals holds the opening elimination of the holding's investments in DSP, SVC and PRT. Business_Combinations "
        "and Business_Disposals hold the two deals. Ownership_Periods names HOLD as the owner of DSP, SVC and PRT. There is no row for ACQ: approving the combination creates it.",
        "Load with: uv run konsol_load.py examples/mini/Mini_Master_Data.xlsx --tb-dir examples/mini/tb -s <frappectl profile>.",
        "The Trial_Balance sheet is HOLD's Activity file, as a format reference. It is not loaded from here. See README.md.",
    )
    write_workbook(path, rows, title="Mini Group — konsolidat onboarding example", intro_lines=intro)
    print("wrote %s" % os.path.relpath(path, HERE))


if __name__ == "__main__":
    build()
