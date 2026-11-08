#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = ["openpyxl>=3.1"]
# ///
"""Build the Aquila Bike Group onboarding example.

    uv run build_aquila_bike.py        -> examples/aquila-bike/Aquila_Bike_Master_Data.xlsx + tb/TB_*.xlsx
                                          + examples/aquila-bike/expected/*.json (the offline model's inputs)

A small, fully worked consolidation case (decided with Deepak Pai, 7 Nov 2026):
ten consolidated legal entities in ten EU countries and five currencies, plus a
30% associate; a joint venture (ABJV) held 30% by ABDE and 30% by ABFR that the group declares
equity-accounted (konsol#117 pair 2); a 70% subsidiary carried at 100% with the minority as the NCI line; one acquisition on 1 June 2024
(goodwill, fair value adjustment, expensed costs); one full disposal on
31 December 2024 (CTA recycled); intercompany trade, fees, loans and interest
on declared account pairs with the partner on both sides; governed monthly
Closing and Average rates and IAS 21 historical equity rates; three reporting
dimensions. Trial balances on the Period-end balance basis: FY2023 P12 (the
opening year end) and FY2024 P1..P12. Every number is deterministic.
"""
from __future__ import annotations

import argparse
import calendar
import json
import os
import random
import sys
import zlib
from collections import defaultdict
from decimal import Decimal

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from konsol_template import SHEETS, TB_HEADER, write_workbook  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
EXAMPLE_DIR = os.path.join(HERE, "examples", "aquila-bike")

GROUP = "AQBIKE"
GROUP_CUR = "EUR"
CHART = "AQBIKE_GROUP"
BASIS = "Period-end balance"
PERIODS = [(2023, 12)] + [(2024, m) for m in range(1, 13)]
ACQ_DATE = "2024-06-01"          # ABCZ: first day of FY2024 P6 (konsolidat#278)
ACQ_PERIOD = (2024, 6)
PRE_ACQ_PERIOD = (2024, 5)       # the acquired balance sheet: 31 May 2024
DSP_DATE = "2024-12-31"          # ABDK: inside FY2024 P12
DSP_PERIOD = (2024, 12)
CONSIDERATION_EUR = 11_000_000   # cash for 100% of ABCZ
ACQ_COSTS_EUR = (("Legal", 180_000), ("Due diligence", 120_000))
FVA_CZK = 25_000_000             # step-up on ABCZ plant (1113)
PROCEEDS_EUR = 7_000_000         # cash for 100% of ABDK


def rng(*parts):
    return random.Random(zlib.crc32("|".join(str(p) for p in parts).encode()))


def R(x):
    return int(round(x))


# ---------------------------------------------------------------------------
# chart of accounts: (code, name, parent, account_type, sub_section, flags, cf)
# flags: G heading, IC allow_ic, C cash, RE retained earnings, hist = historical rate,
#        cr/dr = normal balance override (contra accounts)
# ---------------------------------------------------------------------------
A = []


def acct(code, name, parent, atype, sub, flags="", cf=None):
    A.append((code, name, parent, atype, sub, flags, cf))


acct("1000", "Assets", "", "Asset", "", "G")
acct("1100", "Non-current assets", "1000", "Asset", "Non-current assets", "G")
acct("1110", "Property, plant and equipment", "1100", "Asset", "Non-current assets", "G")
acct("1111", "Land and buildings", "1110", "Asset", "Non-current assets", "", ("Investing", "Purchase of property, plant and equipment"))
acct("1113", "Plant, machinery and tooling", "1110", "Asset", "Non-current assets", "", ("Investing", "Purchase of property, plant and equipment"))
acct("1115", "IT, vehicles and other equipment", "1110", "Asset", "Non-current assets", "", ("Investing", "Purchase of property, plant and equipment"))
acct("1119", "Accumulated depreciation - PPE", "1110", "Asset", "Non-current assets", "cr", ("Operating", "Depreciation and amortisation"))
acct("1120", "Intangible assets", "1100", "Asset", "Non-current assets", "G")
acct("1121", "Goodwill", "1120", "Asset", "Non-current assets", "", ("Investing", "Acquisitions of businesses"))
acct("1122", "Software and brands", "1120", "Asset", "Non-current assets", "", ("Investing", "Purchase of intangible assets"))
acct("1125", "Fair value adjustments on acquisition", "1120", "Asset", "Non-current assets", "", ("Investing", "Acquisitions of businesses"))
acct("1129", "Accumulated amortisation - intangibles", "1120", "Asset", "Non-current assets", "cr", ("Operating", "Depreciation and amortisation"))
acct("1140", "Financial assets", "1100", "Asset", "Non-current assets", "G")
acct("1141", "Investments in subsidiaries", "1140", "Asset", "Non-current assets", "", ("Investing", "Investments in subsidiaries"))
acct("1142", "Investments in associates", "1140", "Asset", "Non-current assets", "", ("Investing", "Investments in associates"))
acct("1144", "Long-term deposits and guarantees", "1140", "Asset", "Non-current assets", "", ("Investing", "Other investments"))
acct("1160", "Long-term intercompany receivables", "1100", "Asset", "Non-current assets", "G")
acct("1161", "Intercompany loans receivable", "1160", "Asset", "Non-current assets", "IC", ("Investing", "Intercompany loans"))
acct("1200", "Current assets", "1000", "Asset", "Current assets", "G")
acct("1210", "Inventories", "1200", "Asset", "Current assets", "G")
acct("1211", "Raw materials and components", "1210", "Asset", "Current assets", "", ("Operating", "Change in inventories"))
acct("1213", "Finished bikes and goods for resale", "1210", "Asset", "Current assets", "", ("Operating", "Change in inventories"))
acct("1219", "Inventory provision", "1210", "Asset", "Current assets", "cr", ("Operating", "Change in inventories"))
acct("1220", "Trade receivables", "1200", "Asset", "Current assets", "G")
acct("1221", "Trade receivables - third parties", "1220", "Asset", "Current assets", "", ("Operating", "Change in trade receivables"))
acct("1222", "Trade receivables - intercompany", "1220", "Asset", "Current assets", "IC", ("Operating", "Change in trade receivables"))
acct("1229", "Allowance for doubtful debts", "1220", "Asset", "Current assets", "cr", ("Operating", "Change in trade receivables"))
acct("1230", "Other receivables", "1200", "Asset", "Current assets", "G")
acct("1231", "Prepayments", "1230", "Asset", "Current assets", "", ("Operating", "Change in other receivables"))
acct("1232", "VAT and other tax receivable", "1230", "Asset", "Current assets", "", ("Operating", "Change in other receivables"))
acct("1235", "Deal settlement account", "1230", "Asset", "Current assets", "", ("Investing", "Acquisitions and disposals of businesses"))
acct("1240", "Cash and cash equivalents", "1200", "Asset", "Current assets", "G")
acct("1241", "Bank current accounts", "1240", "Asset", "Current assets", "C", ("Operating", "Cash and cash equivalents"))
acct("1243", "Petty cash", "1240", "Asset", "Current assets", "C", ("Operating", "Cash and cash equivalents"))

acct("2000", "Liabilities", "", "Liability", "", "G")
acct("2100", "Non-current liabilities", "2000", "Liability", "Non-current liabilities", "G")
acct("2110", "Long-term borrowings", "2100", "Liability", "Non-current liabilities", "G")
acct("2111", "Bank loans - long term", "2110", "Liability", "Non-current liabilities", "", ("Financing", "Proceeds from and repayment of borrowings"))
acct("2114", "Intercompany loans payable", "2110", "Liability", "Non-current liabilities", "IC", ("Financing", "Intercompany loans"))
acct("2120", "Deferred tax", "2100", "Liability", "Non-current liabilities", "G")
acct("2121", "Deferred tax liabilities", "2120", "Liability", "Non-current liabilities", "", ("Operating", "Deferred tax"))
acct("2130", "Long-term provisions", "2100", "Liability", "Non-current liabilities", "G")
acct("2131", "Pension and other long-term provisions", "2130", "Liability", "Non-current liabilities", "", ("Operating", "Change in provisions"))
acct("2200", "Current liabilities", "2000", "Liability", "Current liabilities", "G")
acct("2210", "Trade payables", "2200", "Liability", "Current liabilities", "G")
acct("2211", "Trade payables - third parties", "2210", "Liability", "Current liabilities", "", ("Operating", "Change in trade payables"))
acct("2212", "Trade payables - intercompany", "2210", "Liability", "Current liabilities", "IC", ("Operating", "Change in trade payables"))
acct("2220", "Accruals and deferred income", "2200", "Liability", "Current liabilities", "G")
acct("2221", "Accrued expenses", "2220", "Liability", "Current liabilities", "", ("Operating", "Change in accruals"))
acct("2222", "Accrued payroll and bonuses", "2220", "Liability", "Current liabilities", "", ("Operating", "Change in accruals"))
acct("2223", "Deferred revenue and customer deposits", "2220", "Liability", "Current liabilities", "", ("Operating", "Change in accruals"))
acct("2224", "Accrued interest", "2220", "Liability", "Current liabilities", "", ("Operating", "Change in accruals"))
acct("2230", "Tax liabilities", "2200", "Liability", "Current liabilities", "G")
acct("2231", "VAT payable", "2230", "Liability", "Current liabilities", "", ("Operating", "Change in other tax payables"))
acct("2232", "Income tax payable", "2230", "Liability", "Current liabilities", "", ("Operating", "Income taxes paid"))
acct("2233", "Payroll taxes and social security payable", "2230", "Liability", "Current liabilities", "", ("Operating", "Change in other tax payables"))
acct("2240", "Short-term borrowings", "2200", "Liability", "Current liabilities", "G")
acct("2241", "Bank overdrafts", "2240", "Liability", "Current liabilities", "", ("Financing", "Proceeds from and repayment of borrowings"))
acct("2242", "Current portion of long-term debt", "2240", "Liability", "Current liabilities", "", ("Financing", "Proceeds from and repayment of borrowings"))
acct("2260", "Short-term provisions", "2200", "Liability", "Current liabilities", "G")
acct("2261", "Warranty provisions", "2260", "Liability", "Current liabilities", "", ("Operating", "Change in provisions"))

acct("3000", "Equity", "", "Equity", "Equity", "G")
acct("3100", "Share capital", "3000", "Equity", "Equity", "hist", ("Financing", "Share capital and premium"))
acct("3200", "Share premium", "3000", "Equity", "Equity", "hist", ("Financing", "Share capital and premium"))
acct("3300", "Retained earnings", "3000", "Equity", "Equity", "RE", ("Operating", "Net income"))
acct("3310", "Legal reserve", "3000", "Equity", "Equity", "", ("Financing", "Movements in reserves"))
acct("3700", "Non-controlling interests", "3000", "Equity", "Equity", "closing", ("Financing", "Transactions with non-controlling interests"))

acct("4000", "Revenue", "", "Revenue", "", "G")
acct("4100", "Product revenue", "4000", "Revenue", "Revenue", "G")
acct("4110", "Revenue - e-bikes", "4100", "Revenue", "Revenue")
acct("4120", "Revenue - classic bikes", "4100", "Revenue", "Revenue")
acct("4130", "Revenue - components and accessories", "4100", "Revenue", "Revenue")
acct("4200", "Service revenue", "4000", "Revenue", "Revenue", "G")
acct("4210", "Revenue - workshop and service", "4200", "Revenue", "Revenue")
acct("4220", "Revenue - rental and subscriptions", "4200", "Revenue", "Revenue")
acct("4300", "Intercompany revenue", "4000", "Revenue", "Revenue", "G")
acct("4310", "Intercompany sales of goods", "4300", "Revenue", "Revenue", "IC")
acct("4340", "Intercompany management fee income", "4300", "Revenue", "Revenue", "IC")
acct("4900", "Revenue deductions", "4000", "Revenue", "Revenue", "G")
acct("4910", "Dealer discounts and rebates", "4900", "Revenue", "Revenue", "dr")

acct("5000", "Cost of sales", "", "Expense", "", "G")
acct("5100", "Materials", "5000", "Expense", "Cost of sales", "G")
acct("5110", "Materials and components consumed", "5100", "Expense", "Cost of sales")
acct("5130", "Freight inwards and duties", "5100", "Expense", "Cost of sales")
acct("5200", "Direct labour", "5000", "Expense", "Cost of sales", "G")
acct("5210", "Production and workshop wages", "5200", "Expense", "Cost of sales")
acct("5220", "Production social charges", "5200", "Expense", "Cost of sales")
acct("5300", "Manufacturing overhead", "5000", "Expense", "Cost of sales", "G")
acct("5310", "Depreciation - production assets", "5300", "Expense", "Cost of sales")
acct("5320", "Energy and consumables - production", "5300", "Expense", "Cost of sales")
acct("5400", "Intercompany cost of sales", "5000", "Expense", "Cost of sales", "G")
acct("5410", "Intercompany purchases of goods", "5400", "Expense", "Cost of sales", "IC")
acct("5440", "Intercompany management fees charged", "5400", "Expense", "Cost of sales", "IC")
acct("5500", "Inventory movements", "5000", "Expense", "Cost of sales", "G")
acct("5510", "Change in inventories", "5500", "Expense", "Cost of sales")
acct("5520", "Inventory write-downs", "5500", "Expense", "Cost of sales")

acct("6000", "Operating expenses", "", "Expense", "", "G")
acct("6100", "Personnel expenses", "6000", "Expense", "Operating expenses", "G")
acct("6110", "Salaries and wages", "6100", "Expense", "Operating expenses")
acct("6120", "Social security contributions", "6100", "Expense", "Operating expenses")
acct("6130", "Pension costs", "6100", "Expense", "Operating expenses")
acct("6160", "Travel and subsistence", "6100", "Expense", "Operating expenses")
acct("6200", "Premises and facilities", "6000", "Expense", "Operating expenses", "G")
acct("6210", "Rent and service charges", "6200", "Expense", "Operating expenses")
acct("6220", "Utilities", "6200", "Expense", "Operating expenses")
acct("6230", "Repairs and maintenance", "6200", "Expense", "Operating expenses")
acct("6300", "Selling and marketing", "6000", "Expense", "Operating expenses", "G")
acct("6310", "Advertising and sponsoring", "6300", "Expense", "Operating expenses")
acct("6330", "Dealer commissions", "6300", "Expense", "Operating expenses")
acct("6350", "Freight outwards", "6300", "Expense", "Operating expenses")
acct("6360", "Warranty costs", "6300", "Expense", "Operating expenses")
acct("6400", "Administrative expenses", "6000", "Expense", "Operating expenses", "G")
acct("6410", "Professional and consulting fees", "6400", "Expense", "Operating expenses")
acct("6420", "Audit and accounting fees", "6400", "Expense", "Operating expenses")
acct("6440", "IT licences and cloud services", "6400", "Expense", "Operating expenses")
acct("6470", "Bank charges", "6400", "Expense", "Operating expenses")
acct("6480", "Bad debt expense", "6400", "Expense", "Operating expenses")
acct("6500", "Research and development", "6000", "Expense", "Operating expenses", "G")
acct("6510", "R&D salaries", "6500", "Expense", "Operating expenses")
acct("6520", "Prototypes and test materials", "6500", "Expense", "Operating expenses")
acct("6600", "Depreciation and amortisation", "6000", "Expense", "Operating expenses", "G")
acct("6610", "Depreciation - property, plant and equipment", "6600", "Expense", "Operating expenses")
acct("6620", "Amortisation - intangible assets", "6600", "Expense", "Operating expenses")
acct("6640", "Amortisation - goodwill", "6600", "Expense", "Operating expenses")
acct("6650", "Impairment of non-current assets", "6600", "Expense", "Operating expenses")
acct("6700", "Other operating items", "6000", "Expense", "Operating expenses", "G")
acct("6710", "Other operating expenses", "6700", "Expense", "Operating expenses")
acct("6720", "Operating foreign exchange differences", "6700", "Expense", "Operating expenses")
acct("6730", "Gain or loss on disposal of businesses and assets", "6700", "Expense", "Operating expenses")
acct("6750", "Intercompany differences", "6700", "Expense", "Operating expenses")
acct("6760", "Bargain purchase gain", "6700", "Expense", "Operating expenses", "cr")
acct("6770", "Acquisition-related costs", "6700", "Expense", "Operating expenses")
acct("6790", "Other operating income", "6700", "Expense", "Operating expenses", "cr")

acct("7000", "Financial items", "", "", "Financial items", "G")
acct("7100", "Finance income", "7000", "Revenue", "Financial items", "G")
acct("7110", "Interest income - banks", "7100", "Revenue", "Financial items")
acct("7120", "Intercompany interest income", "7100", "Revenue", "Financial items", "IC")
acct("7140", "Foreign exchange gains - financing", "7100", "Revenue", "Financial items")
acct("7200", "Finance costs", "7000", "Expense", "Financial items", "G")
acct("7210", "Interest expense - bank loans", "7200", "Expense", "Financial items")
acct("7220", "Intercompany interest expense", "7200", "Expense", "Financial items", "IC")
acct("7240", "Foreign exchange losses - financing", "7200", "Expense", "Financial items")

acct("8000", "Income taxes", "", "Expense", "Income taxes", "G")
acct("8100", "Current income tax expense", "8000", "Expense", "Income taxes")

ACCOUNT_NAME = {c: n for c, n, *_ in A}
IC_PAIRS = (("1222", "2212"), ("1161", "2114"), ("4310", "5410"), ("4340", "5440"), ("7120", "7220"))
IC_ACCOUNTS = {a for pair in IC_PAIRS for a in pair}


def chart_rows():
    rows = []
    for code, name, parent, atype, sub, flags, cf in A:
        f = set(flags.split()) if flags else set()
        heading = "G" in f
        section = "" if not atype else ("Balance Sheet" if atype in ("Asset", "Liability", "Equity") else "Profit and Loss")
        if code.startswith("7") and heading and not atype:
            section = "Profit and Loss"
        row = {"main_account": code, "account_name": name, "chart_of_accounts": CHART, "parent_account": parent,
               "is_group": 1 if heading else 0, "account_type": atype, "statement_section": section, "sub_section": sub,
               "status": "Published", "is_posting": 0 if heading else 1}
        if not heading:
            row["normal_balance"] = "Debit" if atype in ("Asset", "Expense") else "Credit"
            if "cr" in f:
                row["normal_balance"] = "Credit"
            if "dr" in f:
                row["normal_balance"] = "Debit"
            row["time_balance"] = "balance" if section == "Balance Sheet" else "flow"
            if section == "Balance Sheet":
                row["fx_method"] = "historical" if "hist" in f else "closing"
            else:
                row["fx_method"] = "average"
            row["allow_ic"] = 1 if "IC" in f else 0
            row["is_cash"] = 1 if "C" in f else 0
            row["is_retained_earnings"] = 1 if "RE" in f else 0
            if cf and section == "Balance Sheet":
                row["cf_category"], row["cf_line_item"] = cf
        rows.append(row)
    return rows


# ---------------------------------------------------------------------------
# dimensions and hierarchies
# ---------------------------------------------------------------------------
# source_column must equal dimension_name on an upload-only site: the bronze budget/GL models read
# vars.dimensions[].source_column from the stg_* staging views, whose columns are dim_<name> (found 7 Nov 2026).
DIMENSIONS = [
    {"dimension_name": "dim_business_line", "source_column": "dim_business_line", "label": "Business line", "cube_type": "string",
     "in_budget": 1, "in_trial_balance": 1, "in_journal": 0, "survives_close": 0, "status": "Published"},
    {"dimension_name": "dim_cost_center", "source_column": "dim_cost_center", "label": "Cost centre", "cube_type": "string",
     "in_budget": 1, "in_trial_balance": 1, "in_journal": 0, "survives_close": 0, "status": "Published"},
    {"dimension_name": "dim_product_group", "source_column": "dim_product_group", "label": "Product group", "cube_type": "string",
     "in_budget": 1, "in_trial_balance": 1, "in_journal": 0, "survives_close": 0, "status": "Published"},
]
HIERARCHIES = [
    {"hierarchy_name": "DIVISIONS", "dimension": "dim_business_line", "label": "Divisions and sub-divisions",
     "effective_from": "2020-01-01", "effective_to": "9999-12-31", "is_default": 1, "status": "Published"},
    {"hierarchy_name": "COST_CENTERS", "dimension": "dim_cost_center", "label": "Cost centre structure",
     "effective_from": "2020-01-01", "effective_to": "9999-12-31", "is_default": 1, "status": "Published"},
    {"hierarchy_name": "PRODUCT_GROUPS", "dimension": "dim_product_group", "label": "Product groups",
     "effective_from": "2020-01-01", "effective_to": "9999-12-31", "is_default": 1, "status": "Published"},
]
# (hierarchy, code, label, parent, is_group)
MEMBERS = [
    ("DIVISIONS", "AQBIKE_GROUP", "Aquila Bike Group", "", 1),
    ("DIVISIONS", "BIKES", "Bikes division", "AQBIKE_GROUP", 1),
    ("DIVISIONS", "BIK_EBIKE", "E-bikes (sub-division)", "BIKES", 0),
    ("DIVISIONS", "BIK_CLASSIC", "Classic bikes (sub-division)", "BIKES", 0),
    ("DIVISIONS", "PARTS_SVC", "Components and services division", "AQBIKE_GROUP", 1),
    ("DIVISIONS", "PAS_COMP", "Components and accessories (sub-division)", "PARTS_SVC", 0),
    ("DIVISIONS", "PAS_SVC", "Service and rental (sub-division)", "PARTS_SVC", 0),
    ("DIVISIONS", "CORPORATE", "Corporate", "AQBIKE_GROUP", 1),
    ("DIVISIONS", "CORP", "Holding and unallocated", "CORPORATE", 0),
    ("COST_CENTERS", "ALL_CC", "All cost centres", "", 1),
    ("COST_CENTERS", "COMMERCIAL", "Commercial", "ALL_CC", 1),
    ("COST_CENTERS", "CC100", "Sales and marketing", "COMMERCIAL", 0),
    ("COST_CENTERS", "OPERATIONS", "Operations", "ALL_CC", 1),
    ("COST_CENTERS", "CC200", "Production, workshop and logistics", "OPERATIONS", 0),
    ("COST_CENTERS", "CC300", "Research and development", "OPERATIONS", 0),
    ("COST_CENTERS", "SUPPORT", "Support functions", "ALL_CC", 1),
    ("COST_CENTERS", "CC400", "Administration, finance and IT", "SUPPORT", 0),
    ("PRODUCT_GROUPS", "ALL_PG", "All product groups", "", 1),
    ("PRODUCT_GROUPS", "PRODUCTS", "Products", "ALL_PG", 1),
    ("PRODUCT_GROUPS", "PG_BIKE", "Complete bikes", "PRODUCTS", 0),
    ("PRODUCT_GROUPS", "PG_FRAME", "Frames and components", "PRODUCTS", 0),
    ("PRODUCT_GROUPS", "PG_ACC", "Accessories and apparel", "PRODUCTS", 0),
    ("PRODUCT_GROUPS", "SERVICES", "Services", "ALL_PG", 1),
    ("PRODUCT_GROUPS", "PG_SVC", "Workshop, rental and subscriptions", "SERVICES", 0),
]


def member_rows():
    return [{"reporting_hierarchy": h, "member_code": c, "member_label": lb, "parent_member_code": p, "is_group": g,
             "effective_from": "2020-01-01", "effective_to": ""} for h, c, lb, p, g in MEMBERS]


# ---------------------------------------------------------------------------
# entities
# code, name, country, currency, management node, kind, business-line mix, size (EUR m revenue; holding: cost base),
# ownership %, method, owned since, first TB period (None = FY2023 P12)
# ---------------------------------------------------------------------------
JV_SINCE = "2024-01-01"
JV_HOLDERS = {"ABJV": (("ABDE", 30), ("ABFR", 30))}      # entity -> ((holder entity, share %), ...): one Ownership Period each
JV_REASON = "joint control under the shareholders' agreement (IFRS 11.7); 60% does not give control"
E = [
    ("ABH", "Aquila Bike Holding N.V.", "NL", "EUR", "AQBIKE", "holding", {"CORP": 1}, 2.4, 100, "full", "2005-01-01", None),
    ("ABDE", "Aquila Bikes Deutschland GmbH", "DE", "EUR", "EBIKES", "ops", {"BIK_EBIKE": .55, "BIK_CLASSIC": .30, "PAS_COMP": .10, "PAS_SVC": .05}, 48, 100, "full", "2008-01-01", None),
    ("ABIT", "Aquila Cicli Italia S.r.l.", "IT", "EUR", "CLASSIC", "ops", {"BIK_CLASSIC": .50, "BIK_EBIKE": .20, "PAS_COMP": .30}, 36, 100, "full", "2010-01-01", None),
    ("ABFR", "Aquila Velo France SAS", "FR", "EUR", "SERVICE", "ops", {"BIK_EBIKE": .35, "BIK_CLASSIC": .25, "PAS_SVC": .30, "PAS_COMP": .10}, 30, 100, "full", "2012-01-01", None),
    ("ABAT", "Aquila Bikes Austria GmbH", "AT", "EUR", "CLASSIC", "ops", {"BIK_CLASSIC": .45, "BIK_EBIKE": .40, "PAS_COMP": .15}, 12, 100, "full", "2014-01-01", None),
    ("ABES", "Aquila Bicicletas Espana S.L.", "ES", "EUR", "SERVICE", "ops", {"PAS_SVC": .60, "BIK_CLASSIC": .25, "PAS_COMP": .15}, 9, 100, "full", "2016-01-01", None),
    ("ABSE", "Aquila Cykel Sverige AB", "SE", "SEK", "EBIKES", "ops", {"BIK_EBIKE": .60, "BIK_CLASSIC": .20, "PAS_SVC": .20}, 18, 70, "full", "2016-07-01", None),
    ("ABPL", "Aquila Rowery Polska Sp. z o.o.", "PL", "PLN", "COMPONENTS", "ops", {"PAS_COMP": .85, "BIK_CLASSIC": .15}, 22, 100, "full", "2011-01-01", None),
    ("ABCZ", "Aquila Kola s.r.o.", "CZ", "CZK", "CLASSIC", "ops", {"BIK_CLASSIC": .55, "BIK_EBIKE": .25, "PAS_COMP": .20}, 14, 100, "full", ACQ_DATE, PRE_ACQ_PERIOD),
    ("ABDK", "Aquila Cykler Danmark A/S", "DK", "DKK", "SERVICE", "ops", {"PAS_SVC": .40, "BIK_EBIKE": .35, "BIK_CLASSIC": .25}, 10, 100, "full", "2015-01-01", None),
    ("ABPT", "Aquila Bicicletas Portugal Lda", "PT", "EUR", "SERVICE", "ops", {"PAS_SVC": .50, "BIK_CLASSIC": .50}, 6, 30, "equity", "2019-01-01", None),
    # konsol#117 pair 2: a joint venture held 30% by ABDE and 30% by ABFR (60% in all, 40% outside); first TB FY2024 P1.
    # "own" is the SUM of the holders' shares; the links are in JV_HOLDERS.
    ("ABJV", "Aquila Shared Mobility B.V.", "NL", "EUR", "SERVICE", "ops", {"PAS_SVC": .70, "BIK_EBIKE": .30}, 4, 60, "equity", JV_SINCE, (2024, 1)),
]
ENT = {e[0]: dict(zip(("code", "name", "country", "cur", "node", "kind", "lines", "size", "own", "method", "since", "first"), e)) for e in E}
CONSOLIDATED = [c for c, e in ENT.items() if e["method"] == "full"]
LEGACY_SUBS = [c for c in CONSOLIDATED if c not in ("ABH", "ABCZ")]          # eliminated by the opening journal
MGMT_NODES = {   # Entity management tree, by division and sub-division
    "AQBIKE": ("Aquila Bike Group (management view)", ""),
    "BIKES_DIV": ("Bikes division", "AQBIKE"),
    "EBIKES": ("E-bikes sub-division", "BIKES_DIV"),
    "CLASSIC": ("Classic bikes sub-division", "BIKES_DIV"),
    "PARTS_DIV": ("Components and services division", "AQBIKE"),
    "COMPONENTS": ("Components sub-division", "PARTS_DIV"),
    "SERVICE": ("Service and rental sub-division", "PARTS_DIV"),
}
TAX = {"NL": .258, "DE": .30, "IT": .24, "FR": .25, "AT": .23, "ES": .25, "SE": .206, "PL": .19, "CZ": .21, "DK": .22, "PT": .21}
PENSION_COUNTRIES = {"DE", "FR", "NL", "AT", "SE"}
RESERVE_COUNTRIES = {"IT", "ES", "PT", "PL", "CZ", "AT"}


def entity_periods(code):
    first = ENT[code]["first"]
    return [p for p in PERIODS if first is None or p >= first]


# ---------------------------------------------------------------------------
# FX: EUR per 1 unit. FY2023 P12 closing = year-end 2023; its Average is declared as the 2023 annual average.
# FY2024: a deterministic monthly walk (DKK pegged, tiny moves).
# ---------------------------------------------------------------------------
BASE_RATE = {"EUR": 1.0, "SEK": 0.0900, "PLN": 0.2300, "CZK": 0.0405, "DKK": 0.1341}
QUOTED_PER = {"SEK": 100, "PLN": 1, "CZK": 100, "DKK": 100}
CURRENCIES = [c for c in BASE_RATE if c != "EUR"]
VOL = {"SEK": 0.007, "PLN": 0.006, "CZK": 0.006, "DKK": 0.0004}


def build_rates():
    rates = {}
    prev = dict(BASE_RATE)
    for i, p in enumerate(PERIODS):
        close, avg = {"EUR": 1.0}, {"EUR": 1.0}
        for cur in CURRENCIES:
            r = rng("fx", cur, p)
            if i == 0:
                c = BASE_RATE[cur]
                a = c * (1 + r.uniform(-0.02, 0.02))
            else:
                c = prev[cur] * (1 + r.gauss(0, VOL[cur]))
                a = (prev[cur] + c) / 2 * (1 + r.uniform(-0.0015, 0.0015))
            qp = QUOTED_PER[cur]
            close[cur] = round(c * qp, 6) / qp
            avg[cur] = round(a * qp, 6) / qp
            prev[cur] = close[cur]
        rates[p] = {"Closing": close, "Average": avg}
    return rates


RATES = build_rates()


def fx_rows():
    rows = []
    for p in PERIODS:
        for rt in ("Closing", "Average"):
            for cur in CURRENCIES:
                qp = QUOTED_PER[cur]
                if p == (2023, 12) and rt == "Average":
                    reason = "2023 annual average rate (ECB reference rates), declared on FY2023 P12 because the whole FY2023 result sits in that period"
                else:
                    reason = "Group treasury rate sheet %s %s" % (rt.lower(), period_name(p))
                rows.append({"to_currency": GROUP_CUR, "from_currency": cur, "fiscal_year": p[0], "fiscal_period": p[1],
                             "rate_type": rt, "quote": round(RATES[p][rt][cur] * qp, 6), "quoted_per": str(qp),
                             "change_reason": reason})
    return rows


def hist_rate(code):
    """The frozen IAS 21 rate (EUR per 1 unit) for the equity of `code`, at its incorporation or acquisition."""
    e = ENT[code]
    if e["cur"] == "EUR":
        return 1.0
    # konsol stores Historical Equity Rate.historical_rate with 6 decimals (EUR per 1 unit): declare
    # exactly what the product will keep, or the replica and the warehouse differ by cents on equity.
    if code == "ABCZ":
        return round(RATES[ACQ_PERIOD]["Closing"]["CZK"], 6)       # acquired 1 June 2024: the P6 closing rate
    r = rng("hist", e["cur"], e["since"][:4])
    qp = QUOTED_PER[e["cur"]]
    return round(round(BASE_RATE[e["cur"]] * (1 + r.uniform(-0.15, 0.20)) * qp, 6) / qp, 6)


def conv(cents, cur_from, cur_to, table):
    if cur_from == cur_to:
        return cents
    return R(cents * table[cur_from] / table[cur_to])


def period_name(p):
    return "FY%d P%02d" % p


# ---------------------------------------------------------------------------
# the operating model
# ---------------------------------------------------------------------------
REV_MIX = {   # business line -> {revenue account: weight}
    "BIK_EBIKE": {"4110": .92, "4130": .08},
    "BIK_CLASSIC": {"4120": .90, "4130": .10},
    "PAS_COMP": {"4130": 1.0},
    "PAS_SVC": {"4210": .60, "4220": .40},
}
PG_OF = {("BIK_EBIKE", "4110"): "PG_BIKE", ("BIK_EBIKE", "4130"): "PG_ACC", ("BIK_CLASSIC", "4120"): "PG_BIKE",
         ("BIK_CLASSIC", "4130"): "PG_ACC", ("PAS_COMP", "4130"): "PG_FRAME", ("PAS_SVC", "4210"): "PG_SVC", ("PAS_SVC", "4220"): "PG_SVC"}
MAIN_PG = {"BIK_EBIKE": "PG_BIKE", "BIK_CLASSIC": "PG_BIKE", "PAS_COMP": "PG_FRAME", "PAS_SVC": "PG_SVC"}
COGS_MIX = {"5110": .56, "5130": .06, "5210": .18, "5220": .05, "5310": .07, "5320": .05, "5520": .03}
OPEX_MIX = {  # account: (weight of opex, cost centre or None for the personnel split)
    "6110": (.30, None), "6120": (.07, None), "6130": (.03, None), "6160": (.02, "CC100"),
    "6210": (.08, "CC200"), "6220": (.03, "CC200"), "6230": (.02, "CC200"),
    "6310": (.08, "CC100"), "6330": (.05, "CC100"), "6350": (.04, "CC200"), "6360": (.02, "CC200"),
    "6410": (.03, "CC400"), "6420": (.01, "CC400"), "6440": (.04, "CC400"), "6470": (.005, "CC400"), "6480": (.01, "CC100"),
    "6510": (.06, "CC300"), "6520": (.03, "CC300"), "6710": (.03, "CC400"),
}
PERSONNEL_SPLIT = {"CC100": .35, "CC200": .40, "CC400": .25}
SEASON_BIKES = [0.60, 0.70, 1.00, 1.30, 1.40, 1.40, 1.20, 1.00, 1.00, 0.90, 0.70, 0.80]
SEASON_SERVICE = [0.85, 0.85, 1.00, 1.10, 1.15, 1.15, 1.10, 1.00, 1.00, 0.95, 0.90, 0.95]

MGMT_FEE = 0.015                                                      # of revenue, charged by ABH to every subsidiary
GOODS = [("ABIT", "ABDE", .12), ("ABIT", "ABFR", .10), ("ABIT", "ABSE", .10), ("ABIT", "ABAT", .12),
         ("ABPL", "ABDE", .08), ("ABPL", "ABIT", .10), ("ABPL", "ABCZ", .06)]   # (seller, buyer, share of buyer revenue)
IC_LOANS = {("ABH", "ABSE"): 25_000_000_00, ("ABH", "ABPL"): 12_000_000_00}  # principal in the borrower's currency (cents)
LOAN_RATE = 0.04
IC_COST_SHARE = 0.72      # a seller's cost of the goods it sells to group companies
RE_FLOOR = 0.04           # opening retained earnings at least this share of revenue (cash makes up the rest)


class Model:
    def __init__(self, code):
        e = ENT[code]
        self.e = e
        r = rng("model", code)
        self.L = 1 / BASE_RATE[e["cur"]]
        self.rev23 = e["size"] * 1e6 * self.L * 100
        self.growth = r.uniform(0.03, 0.09)
        bikes = sum(w for l, w in e["lines"].items() if l.startswith("BIK"))
        self.cogs = r.uniform(0.50, 0.58) if bikes >= .5 else r.uniform(0.44, 0.52)
        self.opex = r.uniform(0.20, 0.27)
        self.dso, self.dsi, self.dpo = r.uniform(35, 60), r.uniform(70, 120) if bikes >= .5 else r.uniform(40, 70), r.uniform(35, 55)
        self.ppe_ratio = r.uniform(0.45, 0.65) if code in ("ABIT", "ABPL") else r.uniform(0.20, 0.35)
        self.loan_ratio = r.uniform(0.10, 0.30)
        self.cash_ratio = r.uniform(0.05, 0.10)
        base = SEASON_BIKES if bikes >= .5 else SEASON_SERVICE
        season = [s * (1 + r.uniform(-0.04, 0.04)) for s in base]
        tot = sum(season)
        self.season = [s * 12 / tot for s in season]

    def rev(self, y, m):
        if self.e["kind"] != "ops":
            return 0
        return self.rev23 * (1 + self.growth) ** (y - 2023) * self.season[m - 1] / 12

    def rev_ytd(self, p):
        y, k = p
        return sum(self.rev(y, m) for m in range(1, k + 1))

    def run_rate(self, p):
        return self.rev(*p) * 12

    def cost_base(self, p):
        y, k = p
        return self.rev23 * (1 + 0.03) ** (y - 2023) * k / 12


ALL_MONTHS = [(2023, m) for m in range(1, 13)] + [(2024, m) for m in range(1, 13)]


def ytd_months(p):
    """The months in period p's year to date, and the two months whose flows are still unpaid at its end."""
    y, k = p
    months = [(y, m) for m in range(1, k + 1)]
    idx = ALL_MONTHS.index((y, k))
    trail = ALL_MONTHS[max(0, idx - 1): idx + 1]
    return months, trail


def pkey(y, m):
    """The governed-rate period a month's flows translate at: FY2023 months use the FY2023 P12 sheet."""
    return (2023, 12) if y == 2023 else (2024, m)


def active(code, y, m):
    """Is the entity part of the group's flows in month (y, m)? ABCZ only from the acquisition."""
    if code == "ABCZ":
        return (y, m) >= ACQ_PERIOD
    return True


def build_ic():
    """{(entity, period): {(account, partner): signed cents}} with both sides at the governed rates."""
    ic = defaultdict(lambda: defaultdict(int))
    models = {c: Model(c) for c in ENT}

    def post(ent, p, account, partner, cents):
        if cents:
            ic[(ent, p)][(account, partner)] += cents

    def flow_pair(payer, payee, pay_acct, income_acct, monthly_fn, p, recv_acct=None, pay_bal_acct=None, months_due=2,
                  third_party=None):
        """A payer-side monthly flow (payer currency) mirrored on the payee at the month's Average rate; the last
        `months_due` months unpaid as receivable / payable at the Closing rate. `third_party` = (active_fn, pay_alt,
        income_alt): months when the pair was not yet in the same group are booked on the third-party accounts with
        no partner and no open balance (settled on completion)."""
        pc, ec = ENT[payer]["cur"], ENT[payee]["cur"]
        months, trail = ytd_months(p)
        active_fn, pay_alt, inc_alt = third_party or ((lambda y, m: True), None, None)
        ic_months = [(y, m) for y, m in months if active_fn(y, m)]
        tp_months = [(y, m) for y, m in months if not active_fn(y, m)]
        post(payer, p, pay_acct, payee, sum(R(monthly_fn(y, m)) for y, m in ic_months))
        post(payee, p, income_acct, payer, -sum(conv(R(monthly_fn(y, m)), pc, ec, RATES[pkey(y, m)]["Average"]) for y, m in ic_months))
        if tp_months:
            post(payer, p, pay_alt, "", sum(R(monthly_fn(y, m)) for y, m in tp_months))
            post(payee, p, inc_alt, "", -sum(conv(R(monthly_fn(y, m)), pc, ec, RATES[pkey(y, m)]["Average"]) for y, m in tp_months))
        if recv_acct:
            due = sum(R(monthly_fn(y, m)) for y, m in trail[-months_due:] if active_fn(y, m))
            post(payer, p, pay_bal_acct, payee, -due)
            post(payee, p, recv_acct, payer, conv(due, pc, ec, RATES[p]["Closing"]))

    for p in PERIODS:
        # management fee from the holding to every consolidated subsidiary (ABCZ from June 2024)
        for code, e in ENT.items():
            if e["kind"] != "ops" or e["method"] != "full":
                continue
            m = models[code]
            flow_pair(code, "ABH", "5440", "4340",
                      lambda y, mm, m=m, c=code: m.rev(y, mm) * MGMT_FEE if active(c, y, mm) else 0, p, "1222", "2212")
        # frames and components between the operating entities. ABPL sold to ABCZ all year: before June those
        # were sales to a company outside the group (4130 at ABPL, 5110 at ABCZ, no partner, settled on
        # completion); from June they are intercompany.
        for seller, buyer, share in GOODS:
            bm = models[buyer]
            tp = ((lambda y, mm, b=buyer: active(b, y, mm)), "5110", "4130") if buyer == "ABCZ" else None
            flow_pair(buyer, seller, "5410", "4310", lambda y, mm, bm=bm, s=share: bm.rev(y, mm) * s, p, "1222", "2212", third_party=tp)
        # loans from the holding, in the borrower's currency; the lender revalues at closing
        for (lender, borrower), principal in IC_LOANS.items():
            lc, bc = ENT[lender]["cur"], ENT[borrower]["cur"]
            post(borrower, p, "2114", lender, -principal)
            post(lender, p, "1161", borrower, conv(principal, bc, lc, RATES[p]["Closing"]))
            reval = conv(principal, bc, lc, RATES[p]["Closing"]) - conv(principal, bc, lc, RATES[PERIODS[0]]["Closing"])
            if reval > 0:
                post(lender, p, "7140", "", -reval)
            elif reval < 0:
                post(lender, p, "7240", "", -reval)
            flow_pair(borrower, lender, "7220", "7120", lambda y, mm, pr=principal: pr * LOAN_RATE / 12, p)
    return ic, models


def equity_of(code, m):
    """(share capital, share premium, legal reserve) in local cents, constant over the example."""
    e = ENT[code]
    if e["kind"] == "ops":
        sc = R(m.rev23 * 0.12 / 1e7) * 10 ** 7
        sp = R(m.rev23 * 0.06 / 1e7) * 10 ** 7
    else:
        sc = R(m.rev23 * 2.0 / 1e7) * 10 ** 7
        sp = R(m.rev23 * 1.0 / 1e7) * 10 ** 7
    lr = R(sc * 0.1) if e["country"] in RESERVE_COUNTRIES else 0
    return sc, sp, lr


def jv_stake_cents(jv, pct, models):
    """A holder's cost of its stake in a joint venture, EUR cents: pct of the JV's share capital + premium (EUR)."""
    sc, sp, _lr = equity_of(jv, models[jv])
    return R((sc + sp) * pct / 100)


def investment_lines(models):
    """The holding's cost of each legacy subsidiary and of the associate, EUR cents, line by line
    (share capital and share premium x ownership x the historical rate) - the figures the opening
    elimination journal reverses to the cent."""
    lines = {}
    for code in LEGACY_SUBS + ["ABPT"]:
        e = ENT[code]
        sc, sp, lr = equity_of(code, models[code])
        h = hist_rate(code)
        lines[code] = {"3100": R(sc * e["own"] / 100 * h), "3200": R(sp * e["own"] / 100 * h)}
    return lines


def entity_rows(code, p, m, ic_rows, models, state):
    """Signed (debit +) local cents by (account, partner, line, cc, pg) for one entity-period: a period-end balance."""
    e = ENT[code]
    rows = defaultdict(int)
    y, k = p
    first = p == entity_periods(code)[0]
    n_months = 12 if p == (2023, 12) else k
    L = m.L

    def put(acct_code, cents, partner="", line="", cc="", pg=""):
        if R(cents):
            rows[(acct_code, partner, line, cc, pg)] += R(cents)

    # ---- P&L (year to date) ----
    if e["kind"] == "ops":
        rev_ytd = m.rev23 if p == (2023, 12) else m.rev_ytd(p)
        for line, lw in e["lines"].items():
            for acct_code, aw in REV_MIX[line].items():
                put(acct_code, -rev_ytd * lw * aw, line=line, pg=PG_OF[(line, acct_code)])
            put("4910", rev_ytd * lw * 0.02, line=line, pg=MAIN_PG[line])
            for acct_code, cw in COGS_MIX.items():
                put(acct_code, rev_ytd * lw * m.cogs * cw, line=line, pg=MAIN_PG[line])
            put("5510", rev_ytd * lw * m.cogs * 0.01 * rng("inv", code, p, line).uniform(-1, 1), line=line, pg=MAIN_PG[line])
        opex_total = rev_ytd * m.opex
    else:
        rev_ytd = 0
        opex_total = m.rev23 if p == (2023, 12) else m.cost_base(p)
    for acct_code, (w, cc) in OPEX_MIX.items():
        amount = opex_total * w
        for line, lw in e["lines"].items():
            if cc is None:
                for pcc, pw in PERSONNEL_SPLIT.items():
                    put(acct_code, amount * lw * pw, line=line, cc=pcc)
            else:
                put(acct_code, amount * lw, line=line, cc=cc)
    put("6790", -opex_total * 0.01, line="CORP" if e["kind"] != "ops" else next(iter(e["lines"])), cc="CC400")
    put("6720", opex_total * 0.003 * rng("fx-op", code, p).uniform(-1, 1), line="CORP" if e["kind"] != "ops" else next(iter(e["lines"])), cc="CC400")

    # fixed assets and their depreciation
    base = m.rev23 if e["kind"] == "ops" else m.rev23 * 0.8
    G = base * m.ppe_ratio
    I = base * 0.04
    dep, amort = G * 0.08 / 12, I * 0.15 / 12
    put("6610", dep * n_months, line="CORP" if e["kind"] != "ops" else next(iter(e["lines"])), cc="CC200")
    put("6620", amort * n_months, line="CORP" if e["kind"] != "ops" else next(iter(e["lines"])), cc="CC400")

    # financing
    T = base * m.loan_ratio if e["kind"] == "ops" else 0
    inv_sub = inv_assoc = 0
    if code == "ABH":
        lines_by_sub = investment_lines(models)
        inv_sub = sum(sum(v.values()) for c, v in lines_by_sub.items() if c != "ABPT")
        inv_assoc = sum(lines_by_sub["ABPT"].values())
        T = R((inv_sub * 0.25) / 1e8) * 10 ** 8
        if p >= ACQ_PERIOD:
            inv_sub += CONSIDERATION_EUR * 100
            T += CONSIDERATION_EUR * 100          # the acquisition is financed with a new term loan
    put("7210", T * 0.045 / 12 * n_months, line="CORP" if e["kind"] != "ops" else next(iter(e["lines"])), cc="CC400")
    put("7110", -base * 0.03 * 0.02 / 12 * n_months, line="CORP" if e["kind"] != "ops" else next(iter(e["lines"])), cc="CC400")

    # intercompany P&L and balances (both sides at the governed rates). Goods bought from a group company
    # replace materials the entity would otherwise buy outside; goods sold to one carry their cost.
    main_line = "CORP" if e["kind"] != "ops" else next(iter(e["lines"]))
    ic_purchases = sum(c for (a, _), c in ic_rows.items() if a == "5410")
    ic_sales = -sum(c for (a, _), c in ic_rows.items() if a == "4310")
    if ic_purchases:
        put("5110", -ic_purchases, line=main_line, pg=MAIN_PG[main_line])
    if ic_sales:
        put("5110", ic_sales * IC_COST_SHARE, line=main_line, pg=MAIN_PG[main_line])
    for (acct_code, partner), cents in ic_rows.items():
        if acct_code[0] not in "4567":
            put(acct_code, cents, partner=partner)                       # balances carry no dimensions
        elif acct_code in ("4130", "5110"):
            put(acct_code, cents, partner=partner, line=main_line, pg=MAIN_PG[main_line])   # third-party trade with the target before the deal
        else:
            put(acct_code, cents, partner=partner, line=main_line, cc="CC400" if acct_code in ("5440", "4340", "7120", "7220", "7140", "7240") else "", pg="" if acct_code in ("5440", "4340", "7120", "7220", "7140", "7240") else MAIN_PG[main_line])

    pbt = -sum(v for (a, *_), v in rows.items() if a[0] in "45678")
    tax = max(pbt, 0) * TAX[e["country"]]
    put("8100", tax, line="CORP" if e["kind"] != "ops" else next(iter(e["lines"])), cc="CC400")
    pnl_total = sum(v for (a, *_), v in rows.items() if a[0] in "45678")

    # ---- balance sheet ----
    rr = m.run_rate(p) if e["kind"] == "ops" else 0
    capex = base * 0.04 / 12 * (0 if p == (2023, 12) else k)
    put("1111", G * 0.35)
    put("1113", G * 0.50 + capex * 0.7)
    put("1115", G * 0.15 + capex * 0.3)
    put("1119", -(0.40 * G + dep * (0 if p == (2023, 12) else k)))
    put("1122", I)
    put("1129", -(0.30 * I + amort * (0 if p == (2023, 12) else k)))
    # a joint venture's holder carries its cost from the formation period: an asset swap, Dr 1142 / Cr cash 1241
    # (cash is the balancing line of every later period; P&L and retained earnings do not move)
    for jv, holders in JV_HOLDERS.items():
        if code in dict(holders) and p >= ENT[jv]["first"]:
            inv_assoc += jv_stake_cents(jv, dict(holders)[code], models)
    put("1141", inv_sub)
    put("1142", inv_assoc)
    put("1144", base * 0.003)
    if e["kind"] == "ops":
        inv = rr * m.cogs * m.dsi / 365
        put("1211", inv * 0.45)
        put("1213", inv * 0.55)
        put("1219", -inv * 0.03)
        recv = rr * m.dso / 365
        put("1221", recv)
        put("1229", -recv * 0.02)
        put("1231", rr * 0.010)
        put("1232", rr * 0.006)
    else:
        put("1231", opex_total / n_months * 0.5)
        put("1232", opex_total / n_months * 0.2)
    put("1243", 1500 * 100 * L)
    # the deal cash the holding parks on the group's settlement account (see README: the deal journals clear it)
    if code == "ABH":
        if p >= ACQ_PERIOD:
            put("1235", sum(c for _, c in ACQ_COSTS_EUR) * 100)
        if p >= DSP_PERIOD:
            put("1235", -PROCEEDS_EUR * 100)
    # liabilities
    put("2111", -(T - T / 10 - (0 if p == (2023, 12) else T / 120 * k)))
    put("2242", -T / 10)
    put("2121", -base * 0.004)
    if e["country"] in PENSION_COUNTRIES:
        put("2131", -base * 0.02)
    if e["kind"] == "ops":
        personnel_rr = rr * m.opex * 0.40
        put("2211", -(rr * m.cogs * 0.75 + rr * m.opex * 0.45) * m.dpo / 365)
        put("2221", -rr * 0.012)
        put("2222", -personnel_rr / 12 * 1.1)
        put("2223", -rr * 0.02)
        put("2224", -(T * 0.045 / 12))
        put("2231", -rr * 0.012)
        put("2233", -personnel_rr / 12 * 0.3)
        put("2261", -rr * 0.006)
    else:
        put("2221", -opex_total / n_months * 0.8)
        put("2222", -opex_total / n_months * 0.4)
        put("2224", -(T * 0.045 / 12))
    put("2232", -tax * (0.25 if p == (2023, 12) else 0.40))
    # equity
    sc, sp, lr = equity_of(code, m)
    put("3100", -sc)
    put("3200", -sp)
    put("3310", -lr)

    # ---- the plugs ----
    if first:
        cash = base * m.cash_ratio if e["kind"] == "ops" else inv_sub * 0.03
        re_open = -(sum(rows.values()) + R(cash))
        if re_open > -RE_FLOOR * base:                      # a credit smaller than the floor: more cash, more reserves
            cash += (re_open + RE_FLOOR * base)
            re_open = -(sum(rows.values()) + R(cash))
        put("1241", cash)
        rows[("3300", "", "", "", "")] += re_open
        state["re_open"] = re_open
        state["pnl_first"] = pnl_total
    else:
        # FY2024 files carry opening retained earnings + the FY2023 result; ABCZ (first file FY2024 P5)
        # keeps its FY2024 result open in the P&L accounts like everyone else, so its retained earnings
        # stay at their P5 figure less the P5 result that was still in the P&L then.
        if ENT[code]["first"] is None:
            rows[("3300", "", "", "", "")] += state["re_open"] + state["pnl_first"]
        else:
            rows[("3300", "", "", "", "")] += state["re_open"]
        cash = -sum(rows.values())
        if cash >= 0:
            put("1241", cash)
        else:
            floor = R(base * 0.01)
            put("1241", floor)
            put("2241", cash - floor)
    assert sum(rows.values()) == 0, (code, p, sum(rows.values()))
    return rows


def build_trial_balances():
    ic, models = build_ic()
    files, summary = {}, []
    states = {c: {} for c in ENT}
    balances = {}   # (entity, period) -> {(account, partner, line, cc, pg): cents}
    for p in PERIODS:
        out = []
        for code, e in ENT.items():
            if p not in entity_periods(code):
                continue
            rows = entity_rows(code, p, models[code], ic[(code, p)], models, states[code])
            balances[(code, p)] = dict(rows)
            dr = cr = 0
            for (acct_code, partner, line, cc, pg), cents in sorted(rows.items()):
                if cents == 0:
                    continue
                d, c = (cents, 0) if cents > 0 else (0, -cents)
                dr += d
                cr += c
                out.append({"data_area_id": code, "fiscal_year": p[0], "fiscal_period": p[1], "main_account": acct_code,
                            "debit": d, "credit": c, "currency": e["cur"], "description": ACCOUNT_NAME[acct_code],
                            "partner_data_area_id": partner, "amount_basis": BASIS,
                            "dim_business_line": line, "dim_cost_center": cc, "dim_product_group": pg})
            assert dr == cr, (code, p, dr, cr)
            summary.append((p, code, dr))
        files[p] = out
    return files, summary, models, balances


# ---------------------------------------------------------------------------
# master-data rows
# ---------------------------------------------------------------------------
def fiscal_rows():
    years, periods = [], []
    for fy in (2023, 2024):
        years.append({"fiscal_year": fy, "start_date": "%d-01-01" % fy, "end_date": "%d-12-31" % fy,
                      "period_pattern": "Monthly (12)", "include_opening_period": 1, "include_closing_period": 1})
        periods.append({"fiscal_year": fy, "fiscal_period": 0, "period_code": "OPN", "period_label": "Opening %d" % fy,
                        "period_type": "Opening", "quarter": "", "start_date": "%d-01-01" % fy, "end_date": "%d-01-01" % fy})
        for mth in range(1, 13):
            last = calendar.monthrange(fy, mth)[1]
            periods.append({"fiscal_year": fy, "fiscal_period": mth, "period_code": "P%02d" % mth,
                            "period_label": "%s %d" % (calendar.month_abbr[mth], fy), "period_type": "Regular",
                            "quarter": "Q%d" % ((mth - 1) // 3 + 1), "start_date": "%d-%02d-01" % (fy, mth),
                            "end_date": "%d-%02d-%02d" % (fy, mth, last)})
        periods.append({"fiscal_year": fy, "fiscal_period": 13, "period_code": "CLS", "period_label": "Closing %d" % fy,
                        "period_type": "Closing", "quarter": "", "start_date": "%d-12-31" % fy, "end_date": "%d-12-31" % fy})
    return years, periods


def entity_sheet_rows():
    rows = []
    for node, (label, parent) in MGMT_NODES.items():
        rows.append({"entity_code": node, "entity_name": label, "parent_entity": parent, "is_group": 1, "status": "Active",
                     "reporting_frequency": "Monthly", "functional_currency": "", "country": "NL" if node == "AQBIKE" else "", "erp_source": ""})
    for code, e in ENT.items():
        rows.append({"entity_code": code, "entity_name": e["name"], "parent_entity": e["node"], "is_group": 0,
                     "status": "Disposed" if code == "ABDK" else "Active", "reporting_frequency": "Monthly",
                     "functional_currency": e["cur"], "country": e["country"], "erp_source": "tb_upload"})
    return rows


POLICY = {"accounting_framework": "IFRS", "goodwill_method": "partial", "goodwill_treatment": "Impairment only",
          "acquisition_costs_treatment": "Expense", "measurement_period": "12 months", "bargain_purchase": "Recognise gain",
          "goodwill_account": "1121", "fair_value_adjustment_account": "1125", "investment_account": "1141",
          "nci_account": "3700", "bargain_purchase_gain_account": "6760", "disposal_gain_loss_account": "6730",
          "disposal_proceeds_account": "1235", "goodwill_amortisation_expense_account": "6640",
          "acquisition_costs_account": "6770", "ic_difference_account": "6750", "ic_difference_tolerance": 500}


def consolidation_rows():
    rows = [{"consolidation_group": GROUP, "data_area_id": "", "entity_name": "Aquila Bike Group (consolidated)", "parent_group": "",
             "is_group": 1, "reporting_currency": GROUP_CUR, **POLICY}]
    for code, e in ENT.items():
        rows.append({"consolidation_group": GROUP, "data_area_id": code, "entity_name": e["name"], "parent_group": GROUP, "is_group": 0})
    return rows


def ownership_links(with_deals=False):
    """One link per Ownership Period: (entity, holder, pct, method, from). holder '' = the group's own node.
    with_deals adds the link the Business Combination creates on approval (ABCZ), for the offline replica."""
    links = []
    for code, e in ENT.items():
        if code == "ABCZ" and not with_deals:
            continue   # created by the Business Combination on approval
        if code in JV_HOLDERS:
            links += [(code, holder, pct, e["method"], e["since"]) for holder, pct in JV_HOLDERS[code]]
        else:
            links.append((code, "", e["own"], e["method"], e["since"]))
    return links


def ownership_rows():
    return [{"consolidation_group": GROUP, "data_area_id": code, "owner_entity": holder, "effective_date": since, "end_date": "",
             "ownership_pct": pct, "consolidation_method": method} for code, holder, pct, method, since in ownership_links()]


def declaration_rows():
    """The method AQBIKE applies to an entity its ownership links reach by more than one path (pair 1 rule)."""
    return [{"consolidation_group": GROUP, "data_area_id": code, "consolidation_method": "equity", "effective_date": JV_SINCE,
             "end_date": "", "reason": JV_REASON} for code in JV_HOLDERS]


def historical_rate_rows():
    rows = []
    for code, e in ENT.items():
        if e["cur"] == GROUP_CUR:
            continue
        for acct_code in ("3100", "3200"):
            rows.append({"consolidation_group": GROUP, "data_area_id": code, "main_account": acct_code,
                         "rate_date": e["since"], "historical_rate": hist_rate(code)})
    return rows


def ic_account_rows():
    return [{"main_account": a, "counterpart_account": b, "status": "Published",
             "description": "%s <-> %s" % (ACCOUNT_NAME[a], ACCOUNT_NAME[b])} for a, b in IC_PAIRS]


def nci_opening_cents(code, balances, models):
    """The minority's opening interest in a partly owned legacy subsidiary, in EUR cents, by equity line:
    share capital and premium at the historical rate (the part of the 100% the holding's investment does not
    cover), legal reserve and opening retained earnings at the FY2023 P12 closing rate. Each line is the
    minority's share (1 - own) of the entity's own translated equity row."""
    e = ENT[code]
    sc, sp, lr = equity_of(code, models[code])
    h = hist_rate(code)
    close = RATES[(2023, 12)]["Closing"][e["cur"]]
    re_cents = -balances[(code, (2023, 12))].get(("3300", "", "", "", ""), 0)      # credit balance, local cents
    own = e["own"] / 100
    return {"3100": R(sc * h) - R(sc * own * h), "3200": R(sp * h) - R(sp * own * h),
            "3310": R(lr * (1 - own) * close), "3300": R(re_cents * (1 - own) * close)}


def opening_journal_rows(models, balances):
    """First consolidation (FY2023 P12): the holding's investments in its greenfield subsidiaries against
    their share capital and premium at the historical rate, to the cent. A partly owned subsidiary is carried
    at 100% (konsolidat#204 option (a)): its whole share capital and premium are eliminated against the
    holding's investment (the group's share) and the non-controlling interests (the rest), and the minority's
    share of its legal reserve and opening retained earnings moves to the NCI line."""
    ref = "CJ-OPEN-2023"
    header = [{"journal_ref": ref, "consolidation_group": GROUP, "adjustment_type": "topside", "fiscal_year": 2023, "fiscal_period": 12,
               "currency": GROUP_CUR, "description": "Opening consolidation: investments in subsidiaries eliminated against their share capital and premium; the minority's interest to the NCI line",
               "reverse_fiscal_year": "", "reverse_fiscal_period": ""}]
    lines, total = [], 0

    def line(code, acct_code, cents, desc):
        """cents > 0 debit, < 0 credit."""
        lines.append({"journal_ref": ref, "data_area_id": code, "main_account": acct_code,
                      "debit_amount": cents / 100 if cents > 0 else "", "credit_amount": -cents / 100 if cents < 0 else "", "description": desc})

    for code, by_acct in investment_lines(models).items():
        if code == "ABPT":
            continue
        own = ENT[code]["own"]
        if own == 100:
            for acct_code, cents in by_acct.items():
                line(code, acct_code, cents, "%s %s x %d%% at the historical rate" % (code, ACCOUNT_NAME[acct_code], own))
                total += cents
            continue
        nci = nci_opening_cents(code, balances, models)
        for acct_code, cents in by_acct.items():
            line(code, acct_code, cents + nci[acct_code], "%s %s eliminated at 100%% at the historical rate" % (code, ACCOUNT_NAME[acct_code]))
            total += cents
        for acct_code in ("3310", "3300"):
            if not nci[acct_code]:
                continue
            line(code, acct_code, nci[acct_code], "%s %s: the %d%% minority's share at the FY2023 P12 closing rate" % (code, ACCOUNT_NAME[acct_code], 100 - own))
        line(code, "3700", -sum(nci.values()), "%s non-controlling interests: %d%% of its equity at the opening" % (code, 100 - own))
    lines.append({"journal_ref": ref, "data_area_id": "ABH", "main_account": "1141", "debit_amount": "", "credit_amount": total / 100,
                  "description": "ABH cost of the subsidiaries"})
    return header, lines


def acquired_balance_sheet(balances):
    """ABCZ's balance sheet at 31 May 2024 (FY2024 P5) as the Business Combination records it: balance-sheet
    accounts at book, the Jan-May result folded into retained earnings (konsol#406), fair value step-up on plant."""
    bal = defaultdict(int)
    pnl = 0
    for (acct_code, *_), cents in balances[("ABCZ", PRE_ACQ_PERIOD)].items():
        if acct_code[0] in "45678":
            pnl += cents
        else:
            bal[acct_code] += cents
    bal["3300"] += pnl
    lines = []
    for acct_code in sorted(bal):
        if bal[acct_code] == 0:
            continue
        lines.append({"main_account": acct_code, "book_amount": bal[acct_code] / 100,
                      "fair_value_adjustment": FVA_CZK if acct_code == "1113" else "", "note": "Balance at 31 May 2024"})
    assert sum(bal.values()) == 0
    return lines


def deal_rows(balances):
    ref = "ACQ-ABCZ-2024"
    bc = [{"deal_ref": ref, "consolidation_group": GROUP, "acquired_entity": "ABCZ", "acquisition_date": ACQ_DATE, "share_acquired_pct": 100,
           "consideration_currency": GROUP_CUR, "nci_measurement_override": "", "nci_fair_value": "", "fair_value_adjustment_total": FVA_CZK,
           "description": "100% of Aquila Kola s.r.o. (Prague) acquired from its founders for cash; plant stepped up to fair value"}]
    cons = [{"deal_ref": ref, "component": "Cash", "amount": CONSIDERATION_EUR, "currency": GROUP_CUR, "settlement_date": ACQ_DATE,
             "description": "Paid on completion"}]
    costs = [{"deal_ref": ref, "kind": kind, "amount": amount, "currency": GROUP_CUR, "description": "%s fees" % kind}
             for kind, amount in ACQ_COSTS_EUR]
    acquired = [dict(deal_ref=ref, **line) for line in acquired_balance_sheet(balances)]
    dref = "DSP-ABDK-2024"
    bd = [{"deal_ref": dref, "consolidation_group": GROUP, "disposed_entity": "ABDK", "disposal_date": DSP_DATE, "share_disposed_pct": 100,
           "retained_interest_pct": 0, "proceeds_currency": GROUP_CUR,
           "description": "100% of Aquila Cykler Danmark A/S sold to a Nordic retail chain, completed 31 December 2024"}]
    proceeds = [{"deal_ref": dref, "component": "Cash", "amount": PROCEEDS_EUR, "currency": GROUP_CUR, "settlement_date": DSP_DATE,
                 "description": "Received on completion"}]
    return {"Business_Combinations": bc, "BC_Consideration": cons, "BC_Acquired_Balances": acquired, "BC_Costs": costs,
            "Business_Disposals": bd, "BD_Proceeds": proceeds}


def master_rows(tb_sample, models, balances):
    years, periods = fiscal_rows()
    cj_header, cj_lines = opening_journal_rows(models, balances)
    rows = {
        "Settings": [{"setting": "default_amount_basis", "value": BASIS}, {"setting": "tb_accepts_opening", "value": "0"},
                     {"setting": "tb_accepts_closing", "value": "0"}, {"setting": "tb_accepts_adjustment", "value": "0"},
                     {"setting": "self_approval", "value": "Allowed with reason"}],   # one person prepares and approves the onboarding load
        "Fiscal_Years": years, "Fiscal_Periods": periods,
        "Entities": entity_sheet_rows(),
        "Dimensions": DIMENSIONS, "Reporting_Hierarchies": HIERARCHIES, "Reporting_Hierarchy_Members": member_rows(),
        "Dimension_Mappings": [],
        "Main_Accounts": chart_rows(), "Intercompany_Accounts": ic_account_rows(),
        "IC_Elimination_Rules": [],
        "Scenarios": [{"scenario_id": "ACTUAL", "scenario_name": "Actual", "scenario_type": "actual", "is_active": 1}],
        "Consolidation_Groups": consolidation_rows(), "Ownership_Periods": ownership_rows(),
        "Method_Declarations": declaration_rows(),
        "FX_Rates": fx_rows(), "Historical_Equity_Rates": historical_rate_rows(),
        "Consolidation_Journals": cj_header, "CJ_Lines": cj_lines,
        "Trial_Balance": tb_sample,
    }
    rows.update(deal_rows(balances))
    known = {s.name for s in SHEETS}
    missing = [k for k in rows if k not in known]
    assert not missing, "sheets not in konsol_template.SHEETS: %s" % missing
    return rows


# ---------------------------------------------------------------------------
# writers
# ---------------------------------------------------------------------------
def write_tb_file(path, rows, p, dims):
    from openpyxl import Workbook
    from openpyxl.styles import Font, PatternFill
    wb = Workbook()
    ws = wb.active
    ws.title = "trial_balance"
    header = list(TB_HEADER) + dims
    ws.append(header)
    for c in ws[1]:
        c.font = Font(name="Arial", bold=True, color="FFFFFF", size=10)
        c.fill = PatternFill("solid", fgColor="1F3864")
    for r in rows:
        ws.append([r["data_area_id"], r["fiscal_year"], r["fiscal_period"], r["main_account"],
                   Decimal(r["debit"]).scaleb(-2) if r["debit"] else None,
                   Decimal(r["credit"]).scaleb(-2) if r["credit"] else None,
                   r["currency"], r["description"], r["partner_data_area_id"] or None, r["amount_basis"]]
                  + [r.get(d) or None for d in dims])
    widths = {"A": 12, "B": 8, "C": 8, "D": 10, "E": 16, "F": 16, "G": 8, "H": 44, "I": 12, "J": 18, "K": 16, "L": 14, "M": 14}
    for col, w in widths.items():
        ws.column_dimensions[col].width = w
    for row in ws.iter_rows(min_row=2, min_col=5, max_col=6):
        for c in row:
            c.number_format = "#,##0.00"
    ws.freeze_panes = "A2"
    ws.auto_filter.ref = ws.dimensions
    about = wb.create_sheet("About")
    entities = sorted({r["data_area_id"] for r in rows})
    for line in (
        "Aquila Bike Group example - bulk trial balance file for %s" % period_name(p),
        "Format: konsol Trial Balance Upload (data on the FIRST sheet). Amount basis: %s." % BASIS,
        "%d rows, %d entities (%s), %d currencies. Debits equal credits exactly per entity in its own currency." % (
            len(rows), len(entities), ", ".join(entities), len({r["currency"] for r in rows})),
        "Intercompany rows carry partner_data_area_id; both sides are booked at the group's governed rates (FX_Rates), so pairs match after translation.",
        "Dimension columns: " + ", ".join(dims) + " (blank = no value).",
        "Generated by excel/onboarding/build_aquila_bike.py; fictional data.",
    ):
        about.append([line])
    about.column_dimensions["A"].width = 160
    wb.save(path)


def write_expected(files, models, balances):
    """The offline model's inputs: balances per entity-period at the (account, partner) grain, rates, ownership,
    hist rates, the deals - what aquila_bike_offline.py consolidates and the walkthrough workbook reads."""
    out_dir = os.path.join(EXAMPLE_DIR, "model")
    os.makedirs(out_dir, exist_ok=True)
    tb = []
    for (code, p), rows in balances.items():
        by = defaultdict(int)
        for (acct_code, partner, *_), cents in rows.items():
            by[(acct_code, partner)] += cents
        for (acct_code, partner), cents in sorted(by.items()):
            if cents:
                tb.append([code, p[0], p[1], acct_code, partner, cents])
    data = {
        "group": GROUP, "group_currency": GROUP_CUR, "periods": PERIODS,
        "entities": {c: {"currency": e["cur"], "own": e["own"], "method": e["method"], "since": e["since"], "name": e["name"]} for c, e in ENT.items()},
        "chart": {code: {"type": atype, "flags": flags, "name": name} for code, name, parent, atype, sub, flags, cf in A if "G" not in (flags or "").split()},
        "rates": {"%d-%d" % p: {rt: RATES[p][rt] for rt in ("Closing", "Average")} for p in PERIODS},
        "hist_rates": {c: hist_rate(c) for c in ENT if ENT[c]["cur"] != GROUP_CUR},
        "ic_pairs": IC_PAIRS, "policy": POLICY,
        "ownership_links": [{"entity": c, "owner": h, "pct": pct, "method": m, "since": since} for c, h, pct, m, since in ownership_links(with_deals=True)],
        "declarations": [{"group": r["consolidation_group"], "entity": r["data_area_id"], "method": r["consolidation_method"],
                          "from": r["effective_date"], "to": r["end_date"], "reason": r["reason"]} for r in declaration_rows()],
        "acquisition": {"entity": "ABCZ", "date": ACQ_DATE, "period": ACQ_PERIOD, "pre_period": PRE_ACQ_PERIOD, "consideration_eur": CONSIDERATION_EUR,
                        "costs_eur": ACQ_COSTS_EUR, "fva_czk": FVA_CZK, "acquired_balances": acquired_balance_sheet(balances)},
        "disposal": {"entity": "ABDK", "date": DSP_DATE, "period": DSP_PERIOD, "proceeds_eur": PROCEEDS_EUR},
        "opening_journal": opening_journal_rows(models, balances)[1],
        "tb_cents": tb,
    }
    with open(os.path.join(out_dir, "inputs.json"), "w") as f:
        json.dump(data, f, indent=1, default=str)
    return os.path.join(out_dir, "inputs.json")


def build_example():
    os.makedirs(os.path.join(EXAMPLE_DIR, "tb"), exist_ok=True)
    files, summary, models, balances = build_trial_balances()
    dims = [d["dimension_name"] for d in DIMENSIONS if d["in_trial_balance"]]
    for p, rows in files.items():
        path = os.path.join(EXAMPLE_DIR, "tb", "TB_FY%d_P%02d.xlsx" % p)
        write_tb_file(path, rows, p, dims)
        print("wrote %s  (%d rows, %d entities)" % (os.path.relpath(path, HERE), len(rows), len({r["data_area_id"] for r in rows})))
    sample = [dict(r, debit=r["debit"] / 100, credit=r["credit"] / 100) for r in files[(2024, 1)] if r["data_area_id"] == "ABDE"][:60]
    rows = master_rows(sample, models, balances)
    rows["Trial_Balance"] = [dict(r, debit=r["debit"] or None, credit=r["credit"] or None) for r in sample]
    path = os.path.join(EXAMPLE_DIR, "Aquila_Bike_Master_Data.xlsx")
    intro = (
        "Filled onboarding workbook for the fictional Aquila Bike Group: %d legal entities in %d EU countries and %d currencies "
        "(ten consolidated, a 30%% associate, and a joint venture held 30%% by ABDE and 30%% by ABFR that AQBIKE declares equity-accounted), a %d-row group chart, %d trial-balance dimensions with %d reporting hierarchies, a flat "
        "consolidation tree under AQBIKE (EUR), a 70%% subsidiary (ABSE, carried at 100%% with the minority as the NCI line), an acquisition on %s (ABCZ, 100%%, goodwill and a fair value "
        "step-up), a full disposal on %s (ABDK), governed monthly FX rates and IAS 21 historical equity rates." % (
            len(ENT), len({e["country"] for e in ENT.values()}), len(BASE_RATE), len(A), len(DIMENSIONS), len(HIERARCHIES), ACQ_DATE, DSP_DATE),
        "Trial balances are in tb/: TB_FY2023_P12.xlsx holds the opening year-end balances (FY2023 P&L still in its accounts, closed to 3300 "
        "by the warehouse in the FY2023 Closing period), then TB_FY2024_P01..P12.xlsx, one upload per month, all on the Period-end balance "
        "basis. ABCZ appears from FY2024 P05 (its 31 May 2024 position, the acquired balance sheet) and ABDK through P12.",
        "Consolidation_Journals holds the opening elimination of the holding's investments against the subsidiaries' share capital; "
        "Business_Combinations and Business_Disposals hold the two deals. See README.md next to this workbook for the walkthrough.",
        "Load with: uv run konsol_load.py examples/aquila-bike/Aquila_Bike_Master_Data.xlsx --tb-dir examples/aquila-bike/tb -s <frappectl profile>.",
        "The Trial_Balance sheet shows the first 60 rows of ABDE in TB_FY2024_P01.xlsx as a format reference; it is not loaded from here.",
    )
    write_workbook(path, rows, title="Aquila Bike Group - konsolidat onboarding example", intro_lines=intro)
    print("wrote %s" % os.path.relpath(path, HERE))
    inputs = write_expected(files, models, balances)
    print("wrote %s" % os.path.relpath(inputs, HERE))
    total = sum(len(v) for v in files.values())
    print("trial balances: %d periods, %d rows, %d entities, all balanced" % (len(files), total, len(ENT)))
    return files, balances


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.parse_args()
    build_example()


if __name__ == "__main__":
    main()
