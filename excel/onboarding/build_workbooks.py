#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = ["openpyxl>=3.1"]
# ///
"""Build the konsolidat onboarding workbooks.

    uv run build_workbooks.py template   -> Konsolidat_Onboarding_Template.xlsx (blank, with examples)
    uv run build_workbooks.py example    -> examples/aquila/Aquila_Group_Master_Data.xlsx + tb/TB_*.xlsx
    uv run build_workbooks.py            -> both

The example is the fictional Aquila Group: 46 legal entities in the EU, UK, US
and India across 10 currencies, a 238-row group chart, 6 dimensions with 3
reporting hierarchies, a 3-level consolidation tree with minority, joint-venture
and associate holdings, governed FX rates, and balanced period-end trial
balances for FY2025 P12 (the opening year-end) and FY2026 P1-P11. Every number
is deterministic (seeded), so a rebuild reproduces the same files.
"""
from __future__ import annotations

import argparse
import calendar
import datetime as dt
import os
import random
import sys
import zlib
from collections import defaultdict
from decimal import Decimal

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from konsol_template import SHEETS, TB_HEADER, write_workbook  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
EXAMPLE_DIR = os.path.join(HERE, "examples", "aquila")

GROUP_CUR = "EUR"
CHART = "AQUILA_GROUP"
BASIS = "Period-end balance"
PERIODS = [(2025, 12)] + [(2026, m) for m in range(1, 12)]   # the opening year end + 11 uploads


def rng(*parts):
    return random.Random(zlib.crc32("|".join(str(p) for p in parts).encode()))


def R(x):
    return int(round(x))


# ---------------------------------------------------------------------------
# chart of accounts: (code, name, parent, flags)   flags: G=heading, IC=allow_ic, C=cash, RE=retained earnings,
# "cr"/"dr" = normal balance override (contra accounts), cf=Category/Line item
# ---------------------------------------------------------------------------
A = []  # (code, name, parent, account_type, sub_section, flags, cf)


def acct(code, name, parent, atype, sub, flags="", cf=None):
    A.append((code, name, parent, atype, sub, flags, cf))


acct("1000", "Assets", "", "Asset", "", "G")
acct("1100", "Non-current assets", "1000", "Asset", "Non-current assets", "G")
acct("1110", "Property, plant and equipment", "1100", "Asset", "Non-current assets", "G")
for c, n in (("1111", "Land"), ("1112", "Buildings"), ("1113", "Plant and machinery"), ("1114", "Vehicles"),
             ("1115", "IT equipment"), ("1116", "Assets under construction")):
    acct(c, n, "1110", "Asset", "Non-current assets", "", ("Investing", "Purchase of property, plant and equipment"))
acct("1119", "Accumulated depreciation - PPE", "1110", "Asset", "Non-current assets", "cr", ("Operating", "Depreciation and amortisation"))
acct("1120", "Intangible assets", "1100", "Asset", "Non-current assets", "G")
for c, n in (("1121", "Goodwill"), ("1122", "Software"), ("1123", "Patents and licences"),
             ("1124", "Customer relationships"), ("1125", "Fair value adjustments on acquisition")):
    acct(c, n, "1120", "Asset", "Non-current assets", "", ("Investing", "Purchase of intangible assets and acquisitions"))
acct("1129", "Accumulated amortisation - intangibles", "1120", "Asset", "Non-current assets", "cr", ("Operating", "Depreciation and amortisation"))
acct("1130", "Right-of-use assets", "1100", "Asset", "Non-current assets", "G")
acct("1131", "Right-of-use assets - buildings", "1130", "Asset", "Non-current assets", "", ("Financing", "Lease additions"))
acct("1132", "Right-of-use assets - vehicles and equipment", "1130", "Asset", "Non-current assets", "", ("Financing", "Lease additions"))
acct("1139", "Accumulated depreciation - right-of-use assets", "1130", "Asset", "Non-current assets", "cr", ("Operating", "Depreciation and amortisation"))
acct("1140", "Financial assets", "1100", "Asset", "Non-current assets", "G")
acct("1141", "Investments in subsidiaries", "1140", "Asset", "Non-current assets", "", ("Investing", "Investments in subsidiaries"))
acct("1142", "Investments in associates and joint ventures", "1140", "Asset", "Non-current assets", "", ("Investing", "Investments in associates"))
acct("1143", "Other long-term investments", "1140", "Asset", "Non-current assets", "", ("Investing", "Other investments"))
acct("1144", "Long-term deposits and guarantees", "1140", "Asset", "Non-current assets", "", ("Investing", "Other investments"))
acct("1150", "Deferred tax assets", "1100", "Asset", "Non-current assets", "G")
acct("1151", "Deferred tax assets", "1150", "Asset", "Non-current assets", "", ("Operating", "Deferred tax"))
acct("1160", "Long-term intercompany receivables", "1100", "Asset", "Non-current assets", "G")
acct("1161", "Intercompany loans receivable - long term", "1160", "Asset", "Non-current assets", "IC", ("Investing", "Intercompany loans"))
acct("1162", "Intercompany interest receivable - long term", "1160", "Asset", "Non-current assets", "IC", ("Investing", "Intercompany loans"))
acct("1200", "Current assets", "1000", "Asset", "Current assets", "G")
acct("1210", "Inventories", "1200", "Asset", "Current assets", "G")
for c, n in (("1211", "Raw materials"), ("1212", "Work in progress"), ("1213", "Finished goods"),
             ("1214", "Spare parts and consumables"), ("1215", "Goods in transit")):
    acct(c, n, "1210", "Asset", "Current assets", "", ("Operating", "Change in inventories"))
acct("1219", "Inventory provision", "1210", "Asset", "Current assets", "cr", ("Operating", "Change in inventories"))
acct("1220", "Trade receivables", "1200", "Asset", "Current assets", "G")
acct("1221", "Trade receivables - third parties", "1220", "Asset", "Current assets", "", ("Operating", "Change in trade receivables"))
acct("1222", "Trade receivables - intercompany", "1220", "Asset", "Current assets", "IC", ("Operating", "Change in trade receivables"))
acct("1223", "Unbilled revenue and contract assets", "1220", "Asset", "Current assets", "", ("Operating", "Change in trade receivables"))
acct("1229", "Allowance for doubtful debts", "1220", "Asset", "Current assets", "cr", ("Operating", "Change in trade receivables"))
acct("1230", "Other receivables", "1200", "Asset", "Current assets", "G")
acct("1231", "Prepayments", "1230", "Asset", "Current assets", "", ("Operating", "Change in other receivables"))
acct("1232", "VAT and indirect tax receivable", "1230", "Asset", "Current assets", "", ("Operating", "Change in other receivables"))
acct("1233", "Other receivables", "1230", "Asset", "Current assets", "", ("Operating", "Change in other receivables"))
acct("1234", "Other intercompany receivables", "1230", "Asset", "Current assets", "IC", ("Operating", "Change in other receivables"))
acct("1235", "Disposal proceeds receivable", "1230", "Asset", "Current assets", "", ("Investing", "Proceeds from disposals"))
acct("1236", "Income tax receivable", "1230", "Asset", "Current assets", "", ("Operating", "Income taxes paid"))
acct("1237", "Employee advances", "1230", "Asset", "Current assets", "", ("Operating", "Change in other receivables"))
acct("1240", "Cash and cash equivalents", "1200", "Asset", "Current assets", "G")
acct("1241", "Bank current accounts", "1240", "Asset", "Current assets", "C", ("Operating", "Cash and cash equivalents"))
acct("1242", "Short-term deposits", "1240", "Asset", "Current assets", "C", ("Operating", "Cash and cash equivalents"))
acct("1243", "Petty cash", "1240", "Asset", "Current assets", "C", ("Operating", "Cash and cash equivalents"))
acct("1244", "Intercompany cash pool receivable", "1240", "Asset", "Current assets", "IC", ("Financing", "Intercompany cash pool"))
acct("1245", "Restricted cash", "1240", "Asset", "Current assets", "", ("Investing", "Restricted cash"))

acct("2000", "Liabilities", "", "Liability", "", "G")
acct("2100", "Non-current liabilities", "2000", "Liability", "Non-current liabilities", "G")
acct("2110", "Long-term borrowings", "2100", "Liability", "Non-current liabilities", "G")
acct("2111", "Bank loans - long term", "2110", "Liability", "Non-current liabilities", "", ("Financing", "Proceeds from and repayment of borrowings"))
acct("2112", "Bonds and notes", "2110", "Liability", "Non-current liabilities", "", ("Financing", "Proceeds from and repayment of borrowings"))
acct("2113", "Lease liabilities - long term", "2110", "Liability", "Non-current liabilities", "", ("Financing", "Lease payments"))
acct("2114", "Intercompany loans payable - long term", "2110", "Liability", "Non-current liabilities", "IC", ("Financing", "Intercompany loans"))
acct("2115", "Intercompany interest payable - long term", "2110", "Liability", "Non-current liabilities", "IC", ("Financing", "Intercompany loans"))
acct("2120", "Deferred tax liabilities", "2100", "Liability", "Non-current liabilities", "G")
acct("2121", "Deferred tax liabilities", "2120", "Liability", "Non-current liabilities", "", ("Operating", "Deferred tax"))
acct("2130", "Long-term provisions", "2100", "Liability", "Non-current liabilities", "G")
for c, n in (("2131", "Pension obligations"), ("2132", "Decommissioning provisions"),
             ("2133", "Other long-term provisions"), ("2134", "Long-term employee benefits")):
    acct(c, n, "2130", "Liability", "Non-current liabilities", "", ("Operating", "Change in provisions"))
acct("2200", "Current liabilities", "2000", "Liability", "Current liabilities", "G")
acct("2210", "Trade payables", "2200", "Liability", "Current liabilities", "G")
acct("2211", "Trade payables - third parties", "2210", "Liability", "Current liabilities", "", ("Operating", "Change in trade payables"))
acct("2212", "Trade payables - intercompany", "2210", "Liability", "Current liabilities", "IC", ("Operating", "Change in trade payables"))
acct("2213", "Payables for fixed assets", "2210", "Liability", "Current liabilities", "", ("Investing", "Purchase of property, plant and equipment"))
acct("2220", "Accruals and deferred income", "2200", "Liability", "Current liabilities", "G")
for c, n in (("2221", "Accrued expenses"), ("2222", "Accrued payroll and bonuses"),
             ("2223", "Deferred revenue and contract liabilities"), ("2224", "Accrued interest")):
    acct(c, n, "2220", "Liability", "Current liabilities", "", ("Operating", "Change in accruals"))
acct("2230", "Tax liabilities", "2200", "Liability", "Current liabilities", "G")
acct("2231", "VAT and indirect tax payable", "2230", "Liability", "Current liabilities", "", ("Operating", "Change in other tax payables"))
acct("2232", "Income tax payable", "2230", "Liability", "Current liabilities", "", ("Operating", "Income taxes paid"))
acct("2233", "Payroll taxes and social security payable", "2230", "Liability", "Current liabilities", "", ("Operating", "Change in other tax payables"))
acct("2234", "Other taxes payable", "2230", "Liability", "Current liabilities", "", ("Operating", "Change in other tax payables"))
acct("2240", "Short-term borrowings", "2200", "Liability", "Current liabilities", "G")
acct("2241", "Bank overdrafts and short-term loans", "2240", "Liability", "Current liabilities", "", ("Financing", "Proceeds from and repayment of borrowings"))
acct("2242", "Current portion of long-term debt", "2240", "Liability", "Current liabilities", "", ("Financing", "Proceeds from and repayment of borrowings"))
acct("2243", "Lease liabilities - short term", "2240", "Liability", "Current liabilities", "", ("Financing", "Lease payments"))
acct("2244", "Intercompany cash pool payable", "2240", "Liability", "Current liabilities", "IC", ("Financing", "Intercompany cash pool"))
acct("2250", "Other payables", "2200", "Liability", "Current liabilities", "G")
acct("2251", "Dividends payable", "2250", "Liability", "Current liabilities", "", ("Financing", "Dividends paid"))
acct("2252", "Other payables", "2250", "Liability", "Current liabilities", "", ("Operating", "Change in other payables"))
acct("2253", "Other intercompany payables", "2250", "Liability", "Current liabilities", "IC", ("Operating", "Change in other payables"))
acct("2254", "Customer deposits received", "2250", "Liability", "Current liabilities", "", ("Operating", "Change in other payables"))
acct("2260", "Short-term provisions", "2200", "Liability", "Current liabilities", "G")
for c, n in (("2261", "Warranty provisions"), ("2262", "Restructuring provisions"), ("2263", "Onerous contract provisions")):
    acct(c, n, "2260", "Liability", "Current liabilities", "", ("Operating", "Change in provisions"))

acct("3000", "Equity", "", "Equity", "Equity", "G")
acct("3100", "Share capital", "3000", "Equity", "Equity", "hist", ("Financing", "Share capital and premium"))
acct("3200", "Share premium", "3000", "Equity", "Equity", "hist", ("Financing", "Share capital and premium"))
acct("3300", "Retained earnings", "3000", "Equity", "Equity", "RE", ("Operating", "Net income"))
acct("3310", "Legal and statutory reserves", "3000", "Equity", "Equity", "", ("Financing", "Movements in reserves"))
acct("3400", "Other reserves", "3000", "Equity", "Equity", "", ("Financing", "Movements in reserves"))
acct("3500", "Currency translation reserve", "3000", "Equity", "Equity", "closing", ("Operating", "Effect of exchange rate changes"))
acct("3600", "Dividends declared", "3000", "Equity", "Equity", "dr", ("Financing", "Dividends paid"))
acct("3700", "Non-controlling interests", "3000", "Equity", "Equity", "closing", ("Financing", "Transactions with non-controlling interests"))
acct("3800", "Hedging reserve", "3000", "Equity", "Equity", "closing", ("Financing", "Movements in reserves"))
acct("3900", "Treasury shares", "3000", "Equity", "Equity", "dr", ("Financing", "Share buy-backs"))

acct("4000", "Revenue", "", "Revenue", "", "G")
acct("4100", "Product revenue", "4000", "Revenue", "Revenue", "G")
for c, n in (("4110", "Revenue - water treatment systems"), ("4120", "Revenue - chemicals and consumables"),
             ("4130", "Revenue - institutional products"), ("4140", "Revenue - spare parts"),
             ("4150", "Revenue - polymers and resins"), ("4160", "Revenue - desalination plants")):
    acct(c, n, "4100", "Revenue", "Revenue")
acct("4200", "Service revenue", "4000", "Revenue", "Revenue", "G")
for c, n in (("4210", "Revenue - maintenance contracts"), ("4220", "Revenue - engineering and consulting"),
             ("4230", "Revenue - installation and commissioning"), ("4240", "Revenue - facility services"),
             ("4250", "Revenue - operating contracts (O&M)")):
    acct(c, n, "4200", "Revenue", "Revenue")
acct("4300", "Intercompany revenue", "4000", "Revenue", "Revenue", "G")
for c, n in (("4310", "Intercompany sales of goods"), ("4320", "Intercompany services rendered"),
             ("4330", "Intercompany royalty and licence income"), ("4340", "Intercompany management fee income")):
    acct(c, n, "4300", "Revenue", "Revenue", "IC")
acct("4900", "Revenue deductions", "4000", "Revenue", "Revenue", "G")
acct("4910", "Sales discounts and rebates", "4900", "Revenue", "Revenue", "dr")
acct("4920", "Sales returns", "4900", "Revenue", "Revenue", "dr")

acct("5000", "Cost of sales", "", "Expense", "", "G")
acct("5100", "Materials", "5000", "Expense", "Cost of sales", "G")
for c, n in (("5110", "Raw materials consumed"), ("5120", "Packaging materials"), ("5130", "Freight inwards and duties"),
             ("5140", "Purchased components"), ("5150", "Subcontracted work")):
    acct(c, n, "5100", "Expense", "Cost of sales")
acct("5200", "Direct labour", "5000", "Expense", "Cost of sales", "G")
for c, n in (("5210", "Production wages"), ("5220", "Production social charges"), ("5230", "Site labour - services")):
    acct(c, n, "5200", "Expense", "Cost of sales")
acct("5300", "Manufacturing overhead", "5000", "Expense", "Cost of sales", "G")
for c, n in (("5310", "Depreciation - production assets"), ("5320", "Energy and utilities - production"),
             ("5330", "Maintenance and repairs - production"), ("5340", "Quality and laboratory costs"),
             ("5350", "Production consumables")):
    acct(c, n, "5300", "Expense", "Cost of sales")
acct("5400", "Intercompany cost of sales", "5000", "Expense", "Cost of sales", "G")
for c, n in (("5410", "Intercompany purchases of goods"), ("5420", "Intercompany services received"),
             ("5430", "Intercompany royalty and licence fees"), ("5440", "Intercompany management fees charged")):
    acct(c, n, "5400", "Expense", "Cost of sales", "IC")
acct("5500", "Inventory movements", "5000", "Expense", "Cost of sales", "G")
for c, n in (("5510", "Change in inventories"), ("5520", "Inventory write-downs"), ("5530", "Purchase price variances")):
    acct(c, n, "5500", "Expense", "Cost of sales")

acct("6000", "Operating expenses", "", "Expense", "", "G")
acct("6100", "Personnel expenses", "6000", "Expense", "Operating expenses", "G")
for c, n in (("6110", "Salaries and wages"), ("6120", "Social security contributions"), ("6130", "Pension costs"),
             ("6140", "Bonuses and incentives"), ("6150", "Training and development"), ("6160", "Travel and subsistence"),
             ("6170", "Recruitment costs"), ("6180", "Contractors and temporary staff"), ("6190", "Other personnel costs")):
    acct(c, n, "6100", "Expense", "Operating expenses")
acct("6200", "Premises and facilities", "6000", "Expense", "Operating expenses", "G")
for c, n in (("6210", "Rent and service charges"), ("6220", "Utilities"), ("6230", "Repairs and maintenance"),
             ("6240", "Insurance"), ("6250", "Security and cleaning")):
    acct(c, n, "6200", "Expense", "Operating expenses")
acct("6300", "Selling and marketing", "6000", "Expense", "Operating expenses", "G")
for c, n in (("6310", "Advertising and promotion"), ("6320", "Trade shows and events"), ("6330", "Sales commissions"),
             ("6340", "Samples and demonstrations"), ("6350", "Freight outwards"), ("6360", "Warranty costs")):
    acct(c, n, "6300", "Expense", "Operating expenses")
acct("6400", "Administrative expenses", "6000", "Expense", "Operating expenses", "G")
for c, n in (("6410", "Professional and consulting fees"), ("6420", "Audit and accounting fees"), ("6430", "Legal fees"),
             ("6440", "IT licences and cloud services"), ("6450", "Telecommunications"), ("6460", "Office supplies and postage"),
             ("6470", "Bank charges"), ("6480", "Bad debt expense"), ("6490", "Subscriptions and memberships")):
    acct(c, n, "6400", "Expense", "Operating expenses")
acct("6500", "Research and development", "6000", "Expense", "Operating expenses", "G")
for c, n in (("6510", "R&D salaries"), ("6520", "R&D materials and prototypes"), ("6530", "External R&D services"),
             ("6540", "Patent and registration costs")):
    acct(c, n, "6500", "Expense", "Operating expenses")
acct("6600", "Depreciation and amortisation", "6000", "Expense", "Operating expenses", "G")
for c, n in (("6610", "Depreciation - property, plant and equipment"), ("6620", "Amortisation - intangible assets"),
             ("6630", "Depreciation - right-of-use assets"), ("6640", "Amortisation - goodwill"),
             ("6650", "Impairment of non-current assets")):
    acct(c, n, "6600", "Expense", "Operating expenses")
acct("6700", "Other operating items", "6000", "Expense", "Operating expenses", "G")
acct("6710", "Other operating expenses", "6700", "Expense", "Operating expenses")
acct("6720", "Operating foreign exchange differences", "6700", "Expense", "Operating expenses")
acct("6730", "Gain or loss on disposal of assets", "6700", "Expense", "Operating expenses")
acct("6740", "Government grants and subsidies", "6700", "Expense", "Operating expenses", "cr")
acct("6750", "Intercompany differences", "6700", "Expense", "Operating expenses")
acct("6760", "Bargain purchase gain", "6700", "Expense", "Operating expenses", "cr")
acct("6770", "Acquisition-related costs", "6700", "Expense", "Operating expenses")
acct("6780", "Restructuring costs", "6700", "Expense", "Operating expenses")
acct("6790", "Other operating income", "6700", "Expense", "Operating expenses", "cr")

acct("7000", "Financial items", "", "", "Financial items", "G")
acct("7100", "Finance income", "7000", "Revenue", "Financial items", "G")
acct("7110", "Interest income - banks and deposits", "7100", "Revenue", "Financial items")
acct("7120", "Intercompany interest income", "7100", "Revenue", "Financial items", "IC")
acct("7130", "Dividend income", "7100", "Revenue", "Financial items")
acct("7140", "Foreign exchange gains - financing", "7100", "Revenue", "Financial items")
acct("7150", "Fair value gains on financial instruments", "7100", "Revenue", "Financial items")
acct("7200", "Finance costs", "7000", "Expense", "Financial items", "G")
acct("7210", "Interest expense - bank loans and bonds", "7200", "Expense", "Financial items")
acct("7220", "Intercompany interest expense", "7200", "Expense", "Financial items", "IC")
acct("7230", "Interest on lease liabilities", "7200", "Expense", "Financial items")
acct("7240", "Foreign exchange losses - financing", "7200", "Expense", "Financial items")
acct("7250", "Financing fees and commitment charges", "7200", "Expense", "Financial items")
acct("7260", "Unwinding of discount on provisions", "7200", "Expense", "Financial items")
acct("7300", "Share of results of associates and joint ventures", "7000", "", "Financial items", "G")
acct("7310", "Share of profit of associates", "7300", "Revenue", "Financial items")
acct("7320", "Share of loss of associates", "7300", "Expense", "Financial items")

acct("8000", "Income taxes", "", "Expense", "Income taxes", "G")
for c, n in (("8100", "Current income tax expense"), ("8200", "Deferred income tax expense"),
             ("8300", "Withholding taxes not recoverable"), ("8400", "Prior-year tax adjustments")):
    acct(c, n, "8000", "Expense", "Income taxes")

ACCOUNT_NAME = {c: n for c, n, *_ in A}
IC_PAIRS = (("1222", "2212"), ("1234", "2253"), ("1161", "2114"), ("1162", "2115"), ("1244", "2244"),
            ("4310", "5410"), ("4320", "5420"), ("4330", "5430"), ("4340", "5440"), ("7120", "7220"))


def chart_rows():
    rows = []
    for code, name, parent, atype, sub, flags, cf in A:
        is_group = "G" in flags.split("|") or flags == "G"
        f = set(flags.split()) if flags else set()
        heading = "G" in f
        section = "" if not atype else ("Balance Sheet" if atype in ("Asset", "Liability", "Equity") else "Profit and Loss")
        if code.startswith("7") and heading and not atype:
            section = "Profit and Loss"
        row = {"main_account": code, "account_name": name, "chart_of_accounts": CHART, "parent_account": parent,
               "is_group": 1 if heading else 0, "account_type": atype, "statement_section": section, "sub_section": sub,
               "status": "Published", "is_posting": 0 if heading else 1}
        if not heading:
            debit_types = {"Asset", "Expense"}
            row["normal_balance"] = "Debit" if atype in debit_types else "Credit"
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
DIMENSIONS = [
    {"dimension_name": "dim_business_line", "source_column": "BusinessLine", "label": "Business line", "cube_type": "string",
     "in_budget": 1, "in_trial_balance": 1, "in_journal": 1, "survives_close": 0, "status": "Published"},
    {"dimension_name": "dim_cost_center", "source_column": "CostCenter", "label": "Cost centre", "cube_type": "string",
     "in_budget": 1, "in_trial_balance": 1, "in_journal": 0, "survives_close": 0, "status": "Published"},
    {"dimension_name": "dim_product_group", "source_column": "ProductGroup", "label": "Product group", "cube_type": "string",
     "in_budget": 1, "in_trial_balance": 1, "in_journal": 0, "survives_close": 0, "status": "Published"},
    {"dimension_name": "dim_project", "source_column": "Project", "label": "Project", "cube_type": "string",
     "in_budget": 1, "in_trial_balance": 0, "in_journal": 0, "survives_close": 0, "status": "Published"},
    {"dimension_name": "dim_channel", "source_column": "SalesChannel", "label": "Sales channel", "cube_type": "string",
     "in_budget": 1, "in_trial_balance": 0, "in_journal": 0, "survives_close": 0, "status": "Published"},
    {"dimension_name": "dim_function", "source_column": "Function", "label": "Function", "cube_type": "string",
     "in_budget": 0, "in_trial_balance": 0, "in_journal": 1, "survives_close": 0, "status": "Published"},
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
    ("DIVISIONS", "AQUILA_GROUP", "Aquila Group", "", 1),
    ("DIVISIONS", "WATER", "Water division", "AQUILA_GROUP", 1),
    ("DIVISIONS", "WAT_MUN", "Municipal water (sub-division)", "WATER", 0),
    ("DIVISIONS", "WAT_IND", "Industrial water (sub-division)", "WATER", 0),
    ("DIVISIONS", "WAT_DES", "Desalination (sub-division)", "WATER", 0),
    ("DIVISIONS", "CHEMICAL", "Chemical division", "AQUILA_GROUP", 1),
    ("DIVISIONS", "CHM_SPC", "Specialty chemicals (sub-division)", "CHEMICAL", 0),
    ("DIVISIONS", "CHM_POL", "Polymers and resins (sub-division)", "CHEMICAL", 0),
    ("DIVISIONS", "CHM_AGR", "Agro chemicals (sub-division)", "CHEMICAL", 0),
    ("DIVISIONS", "INSTITUTIONAL", "Institutional division", "AQUILA_GROUP", 1),
    ("DIVISIONS", "INS_HLT", "Healthcare (sub-division)", "INSTITUTIONAL", 0),
    ("DIVISIONS", "INS_EDU", "Education (sub-division)", "INSTITUTIONAL", 0),
    ("DIVISIONS", "INS_FAC", "Facility services (sub-division)", "INSTITUTIONAL", 0),
    ("DIVISIONS", "CORPORATE", "Corporate", "AQUILA_GROUP", 1),
    ("DIVISIONS", "CORP", "Corporate and holding (unallocated)", "CORPORATE", 0),
    ("COST_CENTERS", "ALL_CC", "All cost centres", "", 1),
    ("COST_CENTERS", "COMMERCIAL", "Commercial", "ALL_CC", 1),
    ("COST_CENTERS", "CC100", "Sales and marketing", "COMMERCIAL", 0),
    ("COST_CENTERS", "OPERATIONS", "Operations", "ALL_CC", 1),
    ("COST_CENTERS", "CC200", "Operations and delivery", "OPERATIONS", 0),
    ("COST_CENTERS", "CC300", "Research and development", "OPERATIONS", 0),
    ("COST_CENTERS", "SUPPORT", "Support functions", "ALL_CC", 1),
    ("COST_CENTERS", "CC400", "General and administration", "SUPPORT", 0),
    ("COST_CENTERS", "CC500", "Finance and IT", "SUPPORT", 0),
    ("PRODUCT_GROUPS", "ALL_PG", "All product groups", "", 1),
    ("PRODUCT_GROUPS", "EQUIPMENT", "Equipment", "ALL_PG", 1),
    ("PRODUCT_GROUPS", "PG_SYS", "Systems and plants", "EQUIPMENT", 0),
    ("PRODUCT_GROUPS", "PG_SPARE", "Spare parts", "EQUIPMENT", 0),
    ("PRODUCT_GROUPS", "RECURRING", "Recurring", "ALL_PG", 1),
    ("PRODUCT_GROUPS", "PG_CONS", "Consumables and chemicals", "RECURRING", 0),
    ("PRODUCT_GROUPS", "PG_SVC", "Services", "RECURRING", 0),
]


def member_rows():
    return [{"reporting_hierarchy": h, "member_code": c, "member_label": lb, "parent_member_code": p, "is_group": g,
             "effective_from": "2020-01-01", "effective_to": ""} for h, c, lb, p, g in MEMBERS]


# ---------------------------------------------------------------------------
# entities
# ---------------------------------------------------------------------------
# code, name, country, currency, consolidation sub-group, kind, business lines, size (EUR m), ownership %, method, since
E = [
    ("AQH", "Aquila Group N.V.", "NL", "EUR", "AQUILA", "holding", {"CORP": 1}, 9, 100, "full", "1998-01-01"),
    ("AQEU", "Aquila Europe B.V.", "NL", "EUR", "AQ_EU", "holding", {"CORP": 1}, 4, 100, "full", "2001-01-01"),
    ("NL01", "Aquila Water Nederland B.V.", "NL", "EUR", "AQ_EU", "ops", {"WAT_MUN": .6, "WAT_IND": .4}, 85, 100, "full", "2001-01-01"),
    ("DE01", "Aquila Wassertechnik GmbH", "DE", "EUR", "AQ_EU", "ops", {"WAT_IND": .7, "WAT_MUN": .3}, 240, 100, "full", "2004-07-01"),
    ("DE02", "Aquila Chemie GmbH", "DE", "EUR", "AQ_EU", "ops", {"CHM_SPC": .6, "CHM_POL": .4}, 310, 100, "full", "2004-07-01"),
    ("DE03", "Aquila Gebaeudeservice GmbH", "DE", "EUR", "AQ_EU", "ops", {"INS_FAC": .7, "INS_HLT": .3}, 95, 100, "full", "2012-03-01"),
    ("DE04", "Aquila-Rhein Wasser JV GmbH", "DE", "EUR", "AQ_EU", "ops", {"WAT_MUN": 1}, 60, 50, "proportional", "2021-01-01"),
    ("FR01", "Aquila Eau SAS", "FR", "EUR", "AQ_EU", "ops", {"WAT_MUN": .5, "WAT_DES": .2, "WAT_IND": .3}, 180, 100, "full", "2006-01-01"),
    ("FR02", "Aquila Chimie SAS", "FR", "EUR", "AQ_EU", "ops", {"CHM_SPC": .5, "CHM_AGR": .5}, 140, 100, "full", "2006-01-01"),
    ("BE01", "Aquila Belgium NV", "BE", "EUR", "AQ_EU", "ops", {"WAT_IND": .5, "INS_FAC": .5}, 45, 100, "full", "2009-01-01"),
    ("ES01", "Aquila Iberia S.L.", "ES", "EUR", "AQ_EU", "ops", {"WAT_MUN": .4, "CHM_AGR": .3, "INS_EDU": .3}, 120, 100, "full", "2008-05-01"),
    ("ES02", "Aquila Desalacion S.A.", "ES", "EUR", "AQ_EU", "ops", {"WAT_DES": 1}, 150, 60, "full", "2016-09-01"),
    ("ES03", "Aquila Agua Andalucia S.A.", "ES", "EUR", "AQ_EU", "ops", {"WAT_MUN": 1}, 35, 40, "equity", "2019-04-01"),
    ("IT01", "Aquila Italia S.r.l.", "IT", "EUR", "AQ_EU", "ops", {"WAT_IND": .4, "CHM_SPC": .3, "INS_HLT": .3}, 110, 100, "full", "2007-01-01"),
    ("PT01", "Aquila Portugal Lda", "PT", "EUR", "AQ_EU", "ops", {"WAT_MUN": .6, "INS_FAC": .4}, 28, 100, "full", "2011-01-01"),
    ("AT01", "Aquila Austria GmbH", "AT", "EUR", "AQ_EU", "ops", {"WAT_IND": .5, "CHM_SPC": .5}, 40, 100, "full", "2010-01-01"),
    ("IE01", "Aquila Ireland Ltd", "IE", "EUR", "AQ_EU", "ops", {"INS_HLT": .6, "WAT_IND": .4}, 38, 100, "full", "2013-01-01"),
    ("FI01", "Aquila Suomi Oy", "FI", "EUR", "AQ_EU", "ops", {"WAT_IND": .6, "CHM_POL": .4}, 42, 100, "full", "2014-01-01"),
    ("GR01", "Aquila Hellas S.A.", "GR", "EUR", "AQ_EU", "ops", {"WAT_DES": .6, "WAT_MUN": .4}, 30, 100, "full", "2017-01-01"),
    ("SK01", "Aquila Slovensko s.r.o.", "SK", "EUR", "AQ_EU", "ops", {"CHM_POL": .7, "WAT_IND": .3}, 22, 100, "full", "2015-06-01"),
    ("LT01", "Aquila Baltic UAB", "LT", "EUR", "AQ_EU", "ops", {"WAT_MUN": .5, "INS_FAC": .5}, 12, 100, "full", "2018-01-01"),
    ("PL01", "Aquila Polska Sp. z o.o.", "PL", "PLN", "AQ_EU", "ops", {"WAT_MUN": .4, "CHM_SPC": .3, "INS_FAC": .3}, 95, 100, "full", "2008-01-01"),
    ("SE01", "Aquila Sverige AB", "SE", "SEK", "AQ_EU", "ops", {"WAT_IND": .5, "INS_HLT": .5}, 70, 100, "full", "2010-01-01"),
    ("DK01", "Aquila Danmark A/S", "DK", "DKK", "AQ_EU", "ops", {"WAT_MUN": .6, "INS_EDU": .4}, 48, 100, "full", "2010-01-01"),
    ("CZ01", "Aquila Cesko s.r.o.", "CZ", "CZK", "AQ_EU", "ops", {"CHM_POL": .6, "WAT_IND": .4}, 55, 100, "full", "2012-01-01"),
    ("HU01", "Aquila Hungaria Kft.", "HU", "HUF", "AQ_EU", "ops", {"CHM_AGR": .6, "WAT_MUN": .4}, 40, 100, "full", "2012-01-01"),
    ("RO01", "Aquila Romania S.R.L.", "RO", "RON", "AQ_EU", "ops", {"WAT_MUN": .5, "INS_FAC": .5}, 35, 75, "full", "2020-10-01"),
    ("AQUK", "Aquila UK Holdings Ltd", "GB", "GBP", "AQ_UK", "holding", {"CORP": 1}, 2.5, 100, "full", "2003-01-01"),
    ("UK01", "Aquila Water Services Ltd", "GB", "GBP", "AQ_UK", "ops", {"WAT_MUN": .5, "WAT_IND": .5}, 160, 100, "full", "2003-01-01"),
    ("UK02", "Aquila Chemicals Ltd", "GB", "GBP", "AQ_UK", "ops", {"CHM_SPC": .7, "CHM_POL": .3}, 120, 100, "full", "2005-04-01"),
    ("UK03", "Aquila Institutional Services Ltd", "GB", "GBP", "AQ_UK", "ops", {"INS_HLT": .4, "INS_EDU": .3, "INS_FAC": .3}, 90, 100, "full", "2011-01-01"),
    ("UK04", "Aquila Scotland Ltd", "GB", "GBP", "AQ_UK", "ops", {"WAT_MUN": 1}, 30, 51, "full", "2022-01-01"),
    ("AQUS", "Aquila Americas Inc.", "US", "USD", "AQ_US", "holding", {"CORP": 1}, 3.5, 100, "full", "2002-01-01"),
    ("US01", "Aquila Water Technologies Inc.", "US", "USD", "AQ_US", "ops", {"WAT_IND": .6, "WAT_MUN": .4}, 320, 100, "full", "2002-01-01"),
    ("US02", "Aquila Specialty Chemicals LLC", "US", "USD", "AQ_US", "ops", {"CHM_SPC": 1}, 260, 100, "full", "2005-01-01"),
    ("US03", "Aquila Institutional Services Inc.", "US", "USD", "AQ_US", "ops", {"INS_HLT": .5, "INS_EDU": .2, "INS_FAC": .3}, 140, 100, "full", "2009-07-01"),
    ("US04", "Aquila Desalination Corp.", "US", "USD", "AQ_US", "ops", {"WAT_DES": 1}, 110, 100, "full", "2014-01-01"),
    ("US05", "Aquila Polymers LLC", "US", "USD", "AQ_US", "ops", {"CHM_POL": 1}, 95, 100, "full", "2016-01-01"),
    ("US06", "Aquila West Water Inc.", "US", "USD", "AQ_US", "ops", {"WAT_MUN": 1}, 60, 80, "full", "2023-07-01"),
    ("AQIN", "Aquila India Holdings Pvt Ltd", "IN", "INR", "AQ_IN", "holding", {"CORP": 1}, 1.2, 100, "full", "2008-01-01"),
    ("IN01", "Aquila Water India Pvt Ltd", "IN", "INR", "AQ_IN", "ops", {"WAT_MUN": .5, "WAT_IND": .5}, 75, 100, "full", "2008-01-01"),
    ("IN02", "Aquila Chemicals India Pvt Ltd", "IN", "INR", "AQ_IN", "ops", {"CHM_SPC": .5, "CHM_AGR": .5}, 90, 100, "full", "2010-01-01"),
    ("IN03", "Aquila Institutional Services India Pvt Ltd", "IN", "INR", "AQ_IN", "ops", {"INS_FAC": .6, "INS_HLT": .4}, 40, 100, "full", "2013-01-01"),
    ("IN04", "Aquila Desal India Pvt Ltd", "IN", "INR", "AQ_IN", "ops", {"WAT_DES": 1}, 55, 74, "full", "2021-04-01"),
    ("IN05", "Aquila Agro Chem Pvt Ltd", "IN", "INR", "AQ_IN", "ops", {"CHM_AGR": 1}, 35, 100, "full", "2015-01-01"),
    ("IN06", "Aquila Membrane Tech Pvt Ltd", "IN", "INR", "AQ_IN", "ops", {"WAT_IND": 1}, 18, 100, "full", "2024-10-01"),
]
ENT = {e[0]: dict(zip(("code", "name", "country", "cur", "group", "kind", "lines", "size", "own", "method", "since"), e)) for e in E}

# consolidation group nodes: code -> (name, parent, reporting currency, management region node)
GROUPS = {
    "AQUILA": ("Aquila Group (consolidated)", "", "EUR"),
    "AQ_EU": ("Aquila Europe sub-group", "AQUILA", "EUR"),
    "AQ_UK": ("Aquila UK sub-group", "AQUILA", "GBP"),
    "AQ_US": ("Aquila Americas sub-group", "AQUILA", "USD"),
    "AQ_IN": ("Aquila India sub-group", "AQUILA", "INR"),
}
GROUP_SINCE = {"AQ_EU": "2001-01-01", "AQ_UK": "2003-01-01", "AQ_US": "2002-01-01", "AQ_IN": "2008-01-01"}
REGION_NODE = {"AQUILA": "AQUILA", "AQ_EU": "EUROPE", "AQ_UK": "UNITED_KINGDOM", "AQ_US": "AMERICAS", "AQ_IN": "INDIA"}
HOLDING_OF = {"AQUILA": "AQH", "AQ_EU": "AQEU", "AQ_UK": "AQUK", "AQ_US": "AQUS", "AQ_IN": "AQIN"}

TAX = {"NL": .258, "DE": .30, "FR": .25, "BE": .25, "ES": .25, "IT": .24, "PT": .21, "AT": .23, "IE": .125, "FI": .20,
       "GR": .22, "SK": .21, "LT": .15, "PL": .19, "SE": .206, "DK": .22, "CZ": .21, "HU": .09, "RO": .16, "GB": .25,
       "US": .26, "IN": .2517}
PENSION_COUNTRIES = {"DE", "FR", "GB", "NL", "AT", "BE", "SE", "FI"}
RESERVE_COUNTRIES = {"FR", "ES", "IT", "PT", "DE", "AT", "GR", "SK", "LT", "PL", "CZ", "HU", "RO", "BE", "IN"}

# ---------------------------------------------------------------------------
# FX: EUR per 1 unit, closing at 2025-12, then a deterministic monthly walk
# ---------------------------------------------------------------------------
BASE_RATE = {"EUR": 1.0, "GBP": 1.1480, "USD": 0.8520, "INR": 0.009550, "PLN": 0.2355, "SEK": 0.0905,
             "DKK": 0.1340, "CZK": 0.0411, "HUF": 0.002560, "RON": 0.1965}
QUOTED_PER = {"GBP": 1, "USD": 1, "INR": 100, "PLN": 1, "SEK": 100, "DKK": 100, "CZK": 100, "HUF": 1000, "RON": 1}
CURRENCIES = [c for c in BASE_RATE if c != "EUR"]


def build_rates():
    """{(year, period): {"Closing": {cur: rate}, "Average": {cur: rate}}} with the rates as the warehouse
    will compute them (quote / quoted_per, quote rounded to 6 places)."""
    rates = {}
    prev = dict(BASE_RATE)
    for i, p in enumerate(PERIODS):
        close, avg = {"EUR": 1.0}, {"EUR": 1.0}
        for cur in CURRENCIES:
            r = rng("fx", cur, p)
            if i == 0:
                c = BASE_RATE[cur]
                a = c * (1 + r.uniform(-0.012, 0.012))
            else:
                c = prev[cur] * (1 + r.gauss(0, 0.009))
                a = (prev[cur] + c) / 2 * (1 + r.uniform(-0.002, 0.002))
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
                rows.append({"to_currency": GROUP_CUR, "from_currency": cur, "fiscal_year": p[0], "fiscal_period": p[1],
                             "rate_type": rt, "quote": round(RATES[p][rt][cur] * qp, 6), "quoted_per": str(qp),
                             "change_reason": "Group treasury rate sheet %s %s" % (rt.lower(), period_name(p))})
    return rows


def hist_rate(cur, since):
    """The frozen IAS 21 rate for equity contributed on `since` (EUR per 1 unit)."""
    if cur == "EUR":
        return 1.0
    r = rng("hist", cur, since[:4])
    return round(BASE_RATE[cur] * (1 + r.uniform(-0.18, 0.22)), 6)


def conv(cents, cur_from, cur_to, table):
    """Integer cents of cur_from -> integer cents of cur_to at the given rate table (EUR per unit)."""
    if cur_from == cur_to:
        return cents
    return R(cents * table[cur_from] / table[cur_to])


def period_name(p):
    return "FY%d P%02d" % p


# ---------------------------------------------------------------------------
# the operating model
# ---------------------------------------------------------------------------
REV_MIX = {   # business line -> {revenue account: weight}
    "WAT_MUN": {"4110": .45, "4210": .20, "4230": .15, "4250": .12, "4140": .08},
    "WAT_IND": {"4110": .50, "4210": .20, "4220": .10, "4140": .12, "4230": .08},
    "WAT_DES": {"4160": .55, "4250": .25, "4230": .12, "4140": .08},
    "CHM_SPC": {"4120": .90, "4220": .10},
    "CHM_POL": {"4150": .92, "4220": .08},
    "CHM_AGR": {"4120": .95, "4220": .05},
    "INS_HLT": {"4130": .35, "4240": .50, "4210": .15},
    "INS_EDU": {"4130": .30, "4240": .60, "4210": .10},
    "INS_FAC": {"4240": .80, "4250": .20},
}
PG_OF_ACCOUNT = {"4110": "PG_SYS", "4160": "PG_SYS", "4120": "PG_CONS", "4130": "PG_CONS", "4150": "PG_CONS",
                 "4140": "PG_SPARE", "4210": "PG_SVC", "4220": "PG_SVC", "4230": "PG_SVC", "4240": "PG_SVC", "4250": "PG_SVC"}
MAIN_PG = {"WAT_MUN": "PG_SYS", "WAT_IND": "PG_SYS", "WAT_DES": "PG_SYS", "CHM_SPC": "PG_CONS", "CHM_POL": "PG_CONS",
           "CHM_AGR": "PG_CONS", "INS_HLT": "PG_SVC", "INS_EDU": "PG_SVC", "INS_FAC": "PG_SVC"}
COGS_MIX = {"5110": .38, "5120": .04, "5130": .05, "5140": .12, "5150": .08, "5210": .12, "5220": .03, "5230": .04,
            "5310": .05, "5320": .04, "5330": .02, "5340": .015, "5350": .015}
OPEX_MIX = {  # account: (weight of opex, cost centre or None for a personnel split)
    "6110": (.30, None), "6120": (.07, None), "6130": (.03, None), "6140": (.04, None), "6150": (.01, "CC400"),
    "6160": (.025, "CC100"), "6170": (.005, "CC400"), "6180": (.03, "CC200"), "6190": (.005, "CC400"),
    "6210": (.05, "CC200"), "6220": (.02, "CC200"), "6230": (.015, "CC200"), "6240": (.012, "CC400"), "6250": (.008, "CC200"),
    "6310": (.035, "CC100"), "6320": (.01, "CC100"), "6330": (.025, "CC100"), "6340": (.005, "CC100"), "6350": (.03, "CC200"),
    "6360": (.01, "CC200"),
    "6410": (.03, "CC400"), "6420": (.01, "CC400"), "6430": (.008, "CC400"), "6440": (.035, "CC500"), "6450": (.007, "CC500"),
    "6460": (.005, "CC400"), "6470": (.004, "CC500"), "6480": (.006, "CC100"), "6490": (.003, "CC400"),
    "6510": (.05, "CC300"), "6520": (.015, "CC300"), "6530": (.02, "CC300"), "6540": (.005, "CC300"),
    "6710": (.03, "CC400"),
}
PERSONNEL_SPLIT = {"CC100": .30, "CC200": .45, "CC400": .25}
SEASON = [0.90, 0.92, 1.00, 1.02, 1.05, 1.10, 1.05, 0.95, 1.05, 1.08, 1.00, 0.88]

# intercompany relationships
MGMT_FEE = {"ops": 0.015, "regional": 0.004}
IC_LOANS = {("AQEU", "DE01"): .15, ("AQEU", "FR01"): .12, ("AQEU", "ES02"): .25, ("AQEU", "PL01"): .20, ("AQEU", "RO01"): .20,
            ("AQEU", "GR01"): .30, ("AQUK", "UK01"): .15, ("AQUK", "UK04"): .30, ("AQUS", "US01"): .10, ("AQUS", "US04"): .35,
            ("AQUS", "US06"): .25, ("AQIN", "IN04"): .30, ("AQIN", "IN06"): .40, ("AQH", "AQUS"): 4.0, ("AQH", "AQIN"): 6.0}
CASH_POOL = {"NL01": .04, "DE02": .05, "FR02": .03, "BE01": .04, "IT01": .03, "AT01": .05, "FI01": .04, "SE01": .03, "DK01": .04,
             "DE03": -.04, "PT01": -.06, "LT01": -.08, "CZ01": -.03, "HU01": -.05, "SK01": -.05}
GOODS = [("DE02", "DE01"), ("DE02", "NL01"), ("DE02", "AT01"), ("DE02", "PL01"), ("DE02", "CZ01"), ("FR02", "FR01"), ("FR02", "ES01"),
         ("FR02", "BE01"), ("FR02", "IT01"), ("UK02", "UK01"), ("UK02", "UK03"), ("UK02", "IE01"), ("US02", "US01"), ("US02", "US04"),
         ("US05", "US03"), ("US02", "DE01"), ("IN02", "IN01"), ("IN02", "IN04"), ("IN05", "HU01"), ("DE02", "IN03")]
SERVICES = [("DE01", "ES02"), ("US01", "US04"), ("UK01", "UK04"), ("IN01", "IN04"), ("FR01", "GR01"), ("DE01", "DE04")]
ROYALTIES = ["DE02", "FR02", "UK02", "US02", "IN02"]


class Model:
    """Per-entity deterministic parameters and the monthly series built from them."""

    def __init__(self, code):
        e = ENT[code]
        self.e = e
        r = rng("model", code)
        self.L = 1 / BASE_RATE[e["cur"]]                      # local units per EUR at the base rate
        self.rev25 = e["size"] * 1e6 * self.L * 100           # annual 2025 revenue, local cents (holdings: cost base)
        self.growth = r.uniform(0.08, 0.14) if e["country"] == "IN" else r.uniform(0.02, 0.09)
        self.cogs = r.uniform(0.52, 0.66)
        self.opex = r.uniform(0.15, 0.23)
        self.dso, self.dsi, self.dpo = r.uniform(40, 75), r.uniform(45, 80), r.uniform(35, 60)
        self.ppe_ratio = r.uniform(0.35, 0.65) if any(l.startswith("WAT") for l in e["lines"]) else r.uniform(0.20, 0.40)
        self.loan_ratio = r.uniform(0.08, 0.30)
        self.cash_ratio = r.uniform(0.05, 0.12)
        season = [s * (1 + r.uniform(-0.05, 0.05)) for s in SEASON]
        if any(l.startswith("INS") for l in e["lines"]):
            season = [s * f for s, f in zip(season, [1.05, 1.05, 1.05, 1.0, 1.0, 0.9, 0.8, 0.85, 1.05, 1.1, 1.1, 1.05])]
        tot = sum(season)
        self.season = [s * 12 / tot for s in season]
        self.wat_share = sum(w for l, w in e["lines"].items() if l.startswith("WAT"))
        self.ins_share = sum(w for l, w in e["lines"].items() if l.startswith("INS"))

    def rev(self, y, m):
        """Revenue of month m of year y, local cents."""
        if self.e["kind"] != "ops":
            return 0
        return self.rev25 * (1 + self.growth) ** (y - 2025) * self.season[m - 1] / 12

    def rev_ytd(self, p):
        y, k = p
        return sum(self.rev(y, m) for m in range(1, k + 1))

    def run_rate(self, p):
        return self.rev(*p) * 12

    def cost_base(self, p):
        """Holdings: overhead YTD (their 'size' is an annual cost base)."""
        y, k = p
        return self.rev25 * (1 + 0.03) ** (y - 2025) * k / 12


def ytd_months(p):
    """The (year, month) list covered by period p's YTD, and the two months behind its balances."""
    y, k = p
    months = [(y, m) for m in range(1, k + 1)]
    trail = [(2025, 12)] * 0
    all_months = [(2025, m) for m in range(1, 13)] + [(2026, m) for m in range(1, 12)]
    idx = all_months.index((y, k))
    trail = all_months[max(0, idx - 1): idx + 1]
    return months, trail


def pkey(y, m):
    """The rate period a month's flows translate at: FY2025 months use the FY2025 P12 sheet."""
    return (2025, 12) if y == 2025 else (2026, m)


def build_ic():
    """Intercompany rows: {(entity, period): {(account, partner): signed cents}} mirrored at group rates."""
    ic = defaultdict(lambda: defaultdict(int))
    models = {c: Model(c) for c in ENT}

    def post(ent, p, account, partner, cents):
        if cents:
            ic[(ent, p)][(account, partner)] += cents

    def flow_pair(payer, payee, pay_acct, income_acct, monthly_fn, p, recv_acct=None, pay_bal_acct=None, months_due=2):
        """A payer-side flow (payer currency) mirrored on the payee at monthly average rates; the unpaid tail
        as receivable/payable at the closing rate."""
        pc, ec = ENT[payer]["cur"], ENT[payee]["cur"]
        months, trail = ytd_months(p)
        exp = sum(R(monthly_fn(y, m)) for y, m in months)
        inc = sum(conv(R(monthly_fn(y, m)), pc, ec, RATES[pkey(y, m)]["Average"]) for y, m in months)
        post(payer, p, pay_acct, payee, exp)
        post(payee, p, income_acct, payer, -inc)
        if recv_acct:
            due = sum(R(monthly_fn(y, m)) for y, m in trail[-months_due:])
            post(payer, p, pay_bal_acct, payee, -due)
            post(payee, p, recv_acct, payer, conv(due, pc, ec, RATES[p]["Closing"]))

    for p in PERIODS:
        for code, e in ENT.items():
            m = models[code]
            if e["kind"] != "ops":
                continue
            holding = HOLDING_OF[e["group"]]
            # management fee from the regional holding
            flow_pair(code, holding, "5440", "4340", lambda y, mm, m=m: m.rev(y, mm) * MGMT_FEE["ops"], p, "1222", "2212")
        # group fee from AQH to the regional holdings, on the region's revenue
        for grp, holding in HOLDING_OF.items():
            if grp == "AQUILA":
                continue
            region_models = [models[c] for c, e in ENT.items() if e["group"] == grp and e["kind"] == "ops"]
            flow_pair(holding, "AQH", "5440", "4340",
                      lambda y, mm, rm=region_models: sum(x.rev(y, mm) for x in rm) * MGMT_FEE["regional"], p, "1234", "2253")
        # royalties on the chemical brands
        for code in ROYALTIES:
            flow_pair(code, "AQH", "5430", "4330", lambda y, mm, m=models[code]: m.rev(y, mm) * 0.005, p, "1234", "2253")
        # goods and services between operating entities
        for seller, buyer in GOODS:
            flow_pair(buyer, seller, "5410", "4310", lambda y, mm, m=models[buyer]: m.rev(y, mm) * 0.03, p, "1222", "2212")
        for provider, client in SERVICES:
            flow_pair(client, provider, "5420", "4320", lambda y, mm, m=models[client]: m.rev(y, mm) * 0.02, p, "1222", "2212")
        # loans: principal in the borrower's currency, interest 4% a year, revalued at the lender at closing
        for (lender, borrower), frac in IC_LOANS.items():
            bm = models[borrower]
            principal = R(bm.rev25 * frac) if ENT[borrower]["kind"] == "ops" else R(bm.rev25 * frac)
            principal = R(principal / 1e6) * 10 ** 6   # round to whole 10,000s
            lc, bc = ENT[lender]["cur"], ENT[borrower]["cur"]
            post(borrower, p, "2114", lender, -principal)
            post(lender, p, "1161", borrower, conv(principal, bc, lc, RATES[p]["Closing"]))
            reval = conv(principal, bc, lc, RATES[p]["Closing"]) - conv(principal, bc, lc, RATES[PERIODS[0]]["Closing"])
            if reval > 0:
                post(lender, p, "7140", "", -reval)
            elif reval < 0:
                post(lender, p, "7240", "", -reval)
            flow_pair(borrower, lender, "7220", "7120", lambda y, mm, pr=principal: pr * 0.04 / 12, p)
        # the cash pool run by AQEU
        for sub, frac in CASH_POOL.items():
            sm = models[sub]
            y, k = p
            bal = R(sm.rev25 * abs(frac) * (1 + 0.1 * rng("pool", sub, p).uniform(-1, 1)))
            sc = ENT[sub]["cur"]
            if frac > 0:
                post(sub, p, "1244", "AQEU", bal)
                post("AQEU", p, "2244", sub, -conv(bal, sc, "EUR", RATES[p]["Closing"]))
            else:
                post(sub, p, "2244", "AQEU", -bal)
                post("AQEU", p, "1244", sub, conv(bal, sc, "EUR", RATES[p]["Closing"]))
    return ic, models


def equity_of(code, m):
    """(share capital, premium, legal reserve) in local cents, constant."""
    e = ENT[code]
    if e["kind"] == "ops":
        sc = R(m.rev25 * 0.15 / 1e7) * 10 ** 7
        sp = R(m.rev25 * 0.08 / 1e7) * 10 ** 7
    else:
        sc = R(m.rev25 * 3.0 / 1e7) * 10 ** 7
        sp = R(m.rev25 * 1.5 / 1e7) * 10 ** 7
    lr = R(sc * 0.1) if e["country"] in RESERVE_COUNTRIES else 0
    return sc, sp, lr


def children_of_holding(holding):
    grp = next(g for g, h in HOLDING_OF.items() if h == holding)
    if grp == "AQUILA":
        return [HOLDING_OF[g] for g in GROUPS if g != "AQUILA"]
    return [c for c, e in ENT.items() if e["group"] == grp and c != holding]


def investments(holding, models):
    """(1141, 1142) at the holding, local cents: the children's equity x ownership at historical rates."""
    hc = ENT[holding]["cur"]
    sub_total, assoc_total = 0, 0
    for child in children_of_holding(holding):
        ce = ENT[child]
        sc, sp, lr = equity_of(child, models[child])
        eq = (sc + sp + lr) * ce["own"] / 100
        h_child, h_hold = hist_rate(ce["cur"], ce["since"]), hist_rate(hc, ENT[holding]["since"]) if hc != "EUR" else 1.0
        amount = R(eq * h_child / h_hold)
        if ce["method"] == "equity":
            assoc_total += amount
        else:
            sub_total += amount
    return sub_total, assoc_total


def entity_rows(code, p, m, ic_rows, models, state):
    """Signed (debit +) cents by (account, partner, line, cc, pg) for one entity-period."""
    e = ENT[code]
    rows = defaultdict(int)
    y, k = p
    first = p == PERIODS[0]
    n_months = 12 if first else k
    L = m.L

    def put(acct_code, cents, partner="", line="", cc="", pg=""):
        if cents:
            rows[(acct_code, partner, line, cc, pg)] += R(cents)

    # ---- P&L (YTD) ----
    if e["kind"] == "ops":
        rev_ytd = m.rev_ytd(p) if not first else m.rev25
        for line, lw in e["lines"].items():
            for acct_code, aw in REV_MIX[line].items():
                put(acct_code, -rev_ytd * lw * aw, line=line, pg=PG_OF_ACCOUNT[acct_code])
            put("4910", rev_ytd * lw * 0.02, line=line, pg=MAIN_PG[line])
            for acct_code, cw in COGS_MIX.items():
                put(acct_code, rev_ytd * lw * m.cogs * cw, line=line, pg=MAIN_PG[line])
            put("5510", rev_ytd * lw * m.cogs * 0.01 * rng("inv", code, p, line).uniform(-1, 1), line=line, pg=MAIN_PG[line])
        opex_total = rev_ytd * m.opex
    else:
        rev_ytd = 0
        opex_total = m.cost_base(p) if not first else m.rev25
    for acct_code, (w, cc) in OPEX_MIX.items():
        amount = opex_total * w
        for line, lw in e["lines"].items():
            if cc is None:
                for pcc, pw in PERSONNEL_SPLIT.items():
                    put(acct_code, amount * lw * pw, line=line, cc=pcc)
            else:
                put(acct_code, amount * lw, line=line, cc=cc)
    put("6790", -opex_total * 0.01, line="CORP" if e["kind"] != "ops" else "", cc="CC400")
    put("6720", opex_total * 0.004 * rng("fx-op", code, p).uniform(-1, 1), cc="CC500")

    # fixed assets and their depreciation
    base = m.rev25 if e["kind"] == "ops" else m.rev25 * 0.8
    G = base * m.ppe_ratio
    I = base * 0.05
    U = base * 0.06
    dep, amort, udep = G * 0.08 / 12, I * 0.10 / 12, U * 0.20 / 12
    put("6610", dep * n_months)
    put("6620", amort * n_months)
    put("6630", udep * n_months)

    # financing
    T = base * m.loan_ratio if e["kind"] == "ops" else 0
    bonds = 0
    sub_inv, assoc_inv = (0, 0)
    if e["kind"] != "ops":
        sub_inv, assoc_inv = investments(code, models)
        if code == "AQH":
            bonds = R((sub_inv * 0.4) / 1e8) * 10 ** 8
        else:
            T = R((sub_inv * 0.2) / 1e8) * 10 ** 8
    lease = (U - 0.35 * U) * 0.9
    put("7210", (T + bonds) * 0.045 / 12 * n_months)
    put("7230", lease * 0.05 / 12 * n_months)
    put("7110", -base * 0.02 * 0.02 / 12 * n_months)
    put("7250", (T + bonds) * 0.002 / 12 * n_months)

    # intercompany P&L and balance rows land here too
    for (acct_code, partner), cents in ic_rows.items():
        put(acct_code, cents, partner=partner)

    pbt = -sum(v for (a, *_), v in rows.items() if a[0] in "45678")
    tax = max(pbt, 0) * TAX[e["country"]]
    put("8100", tax)
    pnl_total = sum(v for (a, *_), v in rows.items() if a[0] in "45678")

    # ---- balance sheet ----
    rr = m.run_rate(p) if e["kind"] == "ops" else 0
    capex = base * 0.04 / 12 * (0 if first else k)
    for acct_code, w in (("1111", .10), ("1112", .30), ("1113", .45), ("1114", .05), ("1115", .07), ("1116", .03)):
        put(acct_code, G * w + (capex * (0.7 if acct_code == "1113" else 0.3 if acct_code == "1116" else 0)))
    put("1119", -(0.40 * G + dep * (0 if first else k)))
    for acct_code, w in (("1122", .5), ("1123", .3), ("1124", .2)):
        put(acct_code, I * w)
    put("1129", -(0.30 * I + amort * (0 if first else k)))
    put("1131", U * 0.8)
    put("1132", U * 0.2)
    put("1139", -(0.35 * U + udep * (0 if first else k)))
    put("1141", sub_inv)
    put("1142", assoc_inv)
    put("1144", base * 0.002)
    put("1151", base * 0.003)
    if e["kind"] == "ops":
        inv = rr * m.cogs * m.dsi / 365
        for acct_code, w in (("1211", .35), ("1212", .15), ("1213", .40), ("1214", .10)):
            put(acct_code, inv * w)
        put("1215", inv * 0.02)
        put("1219", -inv * 0.03)
        recv = rr * m.dso / 365
        put("1221", recv)
        put("1223", recv * 0.10)
        put("1229", -recv * 0.02)
        put("1231", rr * 0.010)
        put("1232", rr * 0.006)
        put("1233", rr * 0.005)
        put("1237", rr * 0.0005)
    else:
        put("1231", opex_total / n_months * 0.5)
        put("1233", opex_total / n_months * 0.3)
    put("1242", base * 0.02)
    put("1243", 1500 * 100 * L)
    # liabilities
    put("2111", T - T / 10 - (0 if first else T / 120 * k))
    put("2242", T / 10)
    put("2112", bonds)
    put("2113", lease * 0.8)
    put("2243", lease * 0.2)
    put("2121", base * 0.004)
    if e["country"] in PENSION_COUNTRIES:
        put("2131", base * 0.02)
    put("2133", base * 0.003)
    if e["kind"] == "ops":
        personnel_rr = rr * m.opex * 0.515
        put("2211", -(rr * m.cogs * 0.75 + rr * m.opex * 0.45) * m.dpo / 365)
        put("2213", -capex * 0.3 if capex else -base * 0.04 / 12 * 0.3)
        put("2221", -rr * 0.012)
        put("2222", -personnel_rr / 12 * 1.1)
        put("2223", -rr * (0.015 + 0.015 * m.ins_share))
        put("2224", -(T * 0.045 / 12))
        put("2231", -rr * 0.012)
        put("2233", -personnel_rr / 12 * 0.3)
        put("2234", -rr * 0.001)
        put("2252", -rr * 0.003)
        put("2254", -rr * 0.02 * m.wat_share)
        put("2261", -rr * 0.005 * m.wat_share)
    else:
        put("2221", -opex_total / n_months * 0.8)
        put("2222", -opex_total / n_months * 0.4)
        put("2224", -(T + bonds) * 0.045 / 12)
    put("2232", -tax * (0.25 if first else 0.40))
    # equity
    sc, sp, lr = equity_of(code, m)
    put("3100", -sc)
    put("3200", -sp)
    put("3310", -lr)
    for sign in (-1, 1):
        pass

    # ---- the plugs ----
    if first:
        cash = base * m.cash_ratio if e["kind"] == "ops" else sub_inv * 0.03
        put("1241", cash)
        re_open = -sum(rows.values())
        rows[("3300", "", "", "", "")] += re_open
        state["re_open"] = re_open
        state["pnl25"] = pnl_total
    else:
        rows[("3300", "", "", "", "")] += state["re_open"] + state["pnl25"]
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
    """{period: [row dict]} for every entity, plus a check summary."""
    ic, models = build_ic()
    files = {}
    summary = []
    states = {c: {} for c in ENT}
    for p in PERIODS:
        out = []
        for code, e in ENT.items():
            rows = entity_rows(code, p, models[code], ic[(code, p)], models, states[code])
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
    return files, summary


# ---------------------------------------------------------------------------
# master-data rows
# ---------------------------------------------------------------------------
def fiscal_rows():
    years, periods = [], []
    for fy in (2025, 2026):
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
    rows = [{"entity_code": "AQUILA", "entity_name": "Aquila Group (management view)", "parent_entity": "", "is_group": 1,
             "status": "Active", "reporting_frequency": "Monthly", "functional_currency": "", "country": "NL", "erp_source": ""}]
    for grp, node in REGION_NODE.items():
        if grp == "AQUILA":
            continue
        label = {"EUROPE": "Europe region", "UNITED_KINGDOM": "United Kingdom region", "AMERICAS": "Americas region", "INDIA": "India region"}[node]
        rows.append({"entity_code": node, "entity_name": label, "parent_entity": "AQUILA", "is_group": 1, "status": "Active",
                     "reporting_frequency": "Monthly", "functional_currency": "", "country": "", "erp_source": ""})
    for code, e in ENT.items():
        rows.append({"entity_code": code, "entity_name": e["name"], "parent_entity": REGION_NODE[e["group"]], "is_group": 0,
                     "status": "Active", "reporting_frequency": "Monthly", "functional_currency": e["cur"], "country": e["country"],
                     "erp_source": "tb_upload"})
    return rows


def consolidation_rows():
    rows = []
    policy = {"accounting_framework": "IFRS", "goodwill_method": "partial", "goodwill_treatment": "Impairment only",
              "acquisition_costs_treatment": "Expense", "measurement_period": "12 months", "bargain_purchase": "Recognise gain",
              "goodwill_account": "1121", "fair_value_adjustment_account": "1125", "investment_account": "1141",
              "nci_account": "3700", "bargain_purchase_gain_account": "6760", "disposal_gain_loss_account": "6730",
              "disposal_proceeds_account": "1235", "goodwill_amortisation_expense_account": "6640",
              "acquisition_costs_account": "6770"}
    for grp, (name, parent, cur) in GROUPS.items():
        row = {"consolidation_group": grp, "data_area_id": "", "entity_name": name, "parent_group": parent, "is_group": 1,
               "reporting_currency": cur, "ic_difference_account": "6750", "ic_difference_tolerance": 1000}
        if grp == "AQUILA":
            row.update(policy)
        rows.append(row)
    for code, e in ENT.items():
        rows.append({"consolidation_group": e["group"], "data_area_id": code, "entity_name": e["name"],
                     "parent_group": e["group"], "is_group": 0})
    return rows


def ownership_rows():
    rows = []
    for grp, since in GROUP_SINCE.items():
        rows.append({"consolidation_group": grp, "data_area_id": "", "effective_date": since, "end_date": "",
                     "ownership_pct": 100, "consolidation_method": "full"})
    for code, e in ENT.items():
        rows.append({"consolidation_group": e["group"], "data_area_id": code, "effective_date": e["since"], "end_date": "",
                     "ownership_pct": e["own"], "consolidation_method": e["method"]})
    return rows


def historical_rate_rows():
    rows = []
    for code, e in ENT.items():
        if e["cur"] == GROUP_CUR:
            continue
        accounts = ["3100", "3200"] + (["3310"] if e["country"] in RESERVE_COUNTRIES else [])
        for acct_code in accounts:
            rows.append({"consolidation_group": "AQUILA", "data_area_id": code, "main_account": acct_code,
                         "rate_date": e["since"], "historical_rate": hist_rate(e["cur"], e["since"])})
    return rows


def ic_account_rows():
    return [{"main_account": a, "counterpart_account": b, "status": "Published",
             "description": "%s <-> %s" % (ACCOUNT_NAME[a], ACCOUNT_NAME[b])} for a, b in IC_PAIRS]


def mapping_rows():
    rows = []
    for src, canon in (("100", "CC100"), ("200", "CC200"), ("300", "CC300"), ("400", "CC400"), ("500", "CC500")):
        rows.append({"dimension": "dim_cost_center", "erp_source": "d365_fo", "entity": "US01", "source_value": src,
                     "canonical_value": canon, "canonical_label": dict((c, lb) for _, c, lb, _, _ in MEMBERS)[canon], "status": "Draft"})
    return rows


def master_rows(tb_sample):
    years, periods = fiscal_rows()
    return {
        "Settings": [{"setting": "default_amount_basis", "value": BASIS}, {"setting": "tb_accepts_opening", "value": "0"},
                     {"setting": "tb_accepts_closing", "value": "0"}, {"setting": "tb_accepts_adjustment", "value": "0"}],
        "Fiscal_Years": years, "Fiscal_Periods": periods,
        "Entities": entity_sheet_rows(),
        "Dimensions": DIMENSIONS, "Reporting_Hierarchies": HIERARCHIES, "Reporting_Hierarchy_Members": member_rows(),
        "Dimension_Mappings": mapping_rows(),
        "Main_Accounts": chart_rows(), "Intercompany_Accounts": ic_account_rows(),
        "IC_Elimination_Rules": [{"rule_id": "UP-INV-01", "rule_name": "Unrealised margin on intercompany inventory",
                                  "rule_type": "unrealized_profit", "debit_account": "4310", "credit_account": "5410",
                                  "debit_entity_pattern": "*", "credit_entity_pattern": "*", "margin_pct": 25,
                                  "asset_account": "1213", "description": "Chemical subsidiaries sell at cost + 25% to water subsidiaries; the margin still in finished goods is eliminated."}],
        "Scenarios": [{"scenario_id": "ACTUAL", "scenario_name": "Actual", "scenario_type": "actual", "is_active": 1},
                      {"scenario_id": "BUDGET_2026", "scenario_name": "Budget 2026", "scenario_type": "budget", "is_active": 1},
                      {"scenario_id": "FORECAST_2026", "scenario_name": "Forecast 2026", "scenario_type": "forecast", "is_active": 1}],
        "Consolidation_Groups": consolidation_rows(), "Ownership_Periods": ownership_rows(),
        "FX_Rates": fx_rows(), "Historical_Equity_Rates": historical_rate_rows(),
        "Trial_Balance": tb_sample,
    }


# ---------------------------------------------------------------------------
# template example rows
# ---------------------------------------------------------------------------
def template_examples():
    return {
        "Settings": [{"setting": "default_amount_basis", "value": "Period-end balance"}, {"setting": "tb_accepts_opening", "value": "0"},
                     {"setting": "self_approval", "value": "Allowed with reason"}],
        "Fiscal_Years": [{"fiscal_year": 2026, "start_date": "2026-01-01", "end_date": "2026-12-31", "period_pattern": "Monthly (12)",
                          "include_opening_period": 1, "include_closing_period": 1}],
        "Fiscal_Periods": [{"fiscal_year": 2026, "fiscal_period": 0, "period_code": "OPN", "period_label": "Opening 2026", "period_type": "Opening",
                            "quarter": "", "start_date": "2026-01-01", "end_date": "2026-01-01"},
                           {"fiscal_year": 2026, "fiscal_period": 1, "period_code": "P01", "period_label": "Jan 2026", "period_type": "Regular",
                            "quarter": "Q1", "start_date": "2026-01-01", "end_date": "2026-01-31"},
                           {"fiscal_year": 2026, "fiscal_period": 13, "period_code": "CLS", "period_label": "Closing 2026", "period_type": "Closing",
                            "quarter": "", "start_date": "2026-12-31", "end_date": "2026-12-31"}],
        "Entities": [{"entity_code": "EXAMPLE_GROUP", "entity_name": "Example Group (management view)", "parent_entity": "", "is_group": 1,
                      "status": "Active", "reporting_frequency": "Monthly", "functional_currency": "", "country": "", "erp_source": ""},
                     {"entity_code": "EXAMPLE_DE01", "entity_name": "Example Deutschland GmbH", "parent_entity": "EXAMPLE_GROUP", "is_group": 0,
                      "status": "Active", "reporting_frequency": "Monthly", "functional_currency": "EUR", "country": "DE", "erp_source": "tb_upload"}],
        "Dimensions": [{"dimension_name": "dim_cost_center", "source_column": "CostCenter", "label": "Cost centre", "cube_type": "string",
                        "in_budget": 1, "in_trial_balance": 1, "in_journal": 0, "survives_close": 0, "status": "Published"}],
        "Reporting_Hierarchies": [{"hierarchy_name": "EXAMPLE_CC_TREE", "dimension": "dim_cost_center", "label": "Cost centres",
                                   "effective_from": "2026-01-01", "effective_to": "9999-12-31", "is_default": 1, "status": "Published"}],
        "Reporting_Hierarchy_Members": [{"reporting_hierarchy": "EXAMPLE_CC_TREE", "member_code": "ALL", "member_label": "All cost centres",
                                         "parent_member_code": "", "is_group": 1, "effective_from": "2026-01-01", "effective_to": ""},
                                        {"reporting_hierarchy": "EXAMPLE_CC_TREE", "member_code": "CC100", "member_label": "Sales",
                                         "parent_member_code": "ALL", "is_group": 0, "effective_from": "2026-01-01", "effective_to": ""}],
        "Dimension_Mappings": [{"dimension": "dim_cost_center", "erp_source": "d365_fo", "entity": "", "source_value": "100",
                                "canonical_value": "CC100", "canonical_label": "Sales", "status": "Published"}],
        "Main_Accounts": [{"main_account": "EXAMPLE_1200", "account_name": "Current assets", "chart_of_accounts": "GROUP", "parent_account": "",
                           "is_group": 1, "account_type": "Asset", "statement_section": "Balance Sheet", "is_posting": 0, "status": "Published"},
                          {"main_account": "EXAMPLE_1241", "account_name": "Bank current accounts", "chart_of_accounts": "GROUP",
                           "parent_account": "EXAMPLE_1200", "is_group": 0, "account_type": "Asset", "statement_section": "Balance Sheet",
                           "sub_section": "Current assets", "normal_balance": "Debit", "time_balance": "balance", "fx_method": "closing",
                           "is_posting": 1, "allow_ic": 0, "is_cash": 1, "is_retained_earnings": 0, "cf_category": "Operating",
                           "cf_line_item": "Cash and cash equivalents", "status": "Published"}],
        "Intercompany_Accounts": [{"main_account": "EXAMPLE_1222", "counterpart_account": "EXAMPLE_2212", "status": "Published",
                                   "description": "IC receivable <-> IC payable"}],
        "IC_Elimination_Rules": [{"rule_id": "EXAMPLE_UP_INV", "rule_name": "Unrealised profit in inventory", "rule_type": "unrealized_profit",
                                  "debit_account": "EXAMPLE_4310", "credit_account": "EXAMPLE_5410", "debit_entity_pattern": "*",
                                  "credit_entity_pattern": "*", "margin_pct": 25, "asset_account": "EXAMPLE_1213", "description": ""}],
        "Scenarios": [{"scenario_id": "ACTUAL", "scenario_name": "Actual", "scenario_type": "actual", "is_active": 1}],
        "Consolidation_Groups": [{"consolidation_group": "EXAMPLE_GRP", "data_area_id": "", "entity_name": "Example Group", "parent_group": "",
                                  "is_group": 1, "reporting_currency": "EUR", "accounting_framework": "IFRS", "goodwill_method": "partial",
                                  "ic_difference_account": "EXAMPLE_6750", "ic_difference_tolerance": 1000},
                                 {"consolidation_group": "EXAMPLE_GRP", "data_area_id": "EXAMPLE_DE01", "entity_name": "Example Deutschland GmbH",
                                  "parent_group": "EXAMPLE_GRP", "is_group": 0}],
        "Ownership_Periods": [{"consolidation_group": "EXAMPLE_GRP", "data_area_id": "EXAMPLE_DE01", "effective_date": "2015-01-01", "end_date": "",
                               "ownership_pct": 100, "consolidation_method": "full"}],
        "FX_Rates": [{"to_currency": "EUR", "from_currency": "USD", "fiscal_year": 2026, "fiscal_period": 1, "rate_type": "Closing",
                      "quote": 0.8520, "quoted_per": "1", "change_reason": "ECB reference rate 2026-01-30"},
                     {"to_currency": "EUR", "from_currency": "INR", "fiscal_year": 2026, "fiscal_period": 1, "rate_type": "Average",
                      "quote": 0.9550, "quoted_per": "100", "change_reason": "Monthly average of ECB reference rates"}],
        "Historical_Equity_Rates": [{"consolidation_group": "EXAMPLE_GRP", "data_area_id": "EXAMPLE_US01", "main_account": "EXAMPLE_3100",
                                     "rate_date": "2015-01-01", "historical_rate": 0.8237}],
        # first consolidation: eliminate the parent's investment in EXAMPLE_DE01 against its share capital
        "Consolidation_Journals": [{"journal_ref": "EXAMPLE_CJ-2026-01-INV", "consolidation_group": "EXAMPLE_GRP", "adjustment_type": "topside",
                                    "fiscal_year": 2026, "fiscal_period": 1, "currency": "EUR",
                                    "description": "Opening elimination: investment in Example Deutschland GmbH against its share capital",
                                    "reverse_fiscal_year": "", "reverse_fiscal_period": ""}],
        "CJ_Lines": [{"journal_ref": "EXAMPLE_CJ-2026-01-INV", "data_area_id": "EXAMPLE_DE01", "main_account": "EXAMPLE_3100",
                      "debit_amount": 500000.00, "credit_amount": "", "description": "Share capital of the subsidiary"},
                     {"journal_ref": "EXAMPLE_CJ-2026-01-INV", "data_area_id": "EXAMPLE_NL01", "main_account": "EXAMPLE_1500",
                      "debit_amount": "", "credit_amount": 500000.00, "description": "Investment in subsidiaries held by the parent"}],
        # EXAMPLE_GRP acquires EXAMPLE_CZ01 on the first day of P6 for 1,000,000 EUR cash ...
        "Business_Combinations": [{"deal_ref": "EXAMPLE_ACQ-CZ01-2026", "consolidation_group": "EXAMPLE_GRP", "acquired_entity": "EXAMPLE_CZ01",
                                   "acquisition_date": "2026-06-01", "share_acquired_pct": 100, "consideration_currency": "EUR",
                                   "nci_measurement_override": "", "nci_fair_value": "", "fair_value_adjustment_total": "",
                                   "description": "Acquisition of Example Czechia s.r.o., 100% for cash"}],
        "BC_Consideration": [{"deal_ref": "EXAMPLE_ACQ-CZ01-2026", "component": "Cash", "amount": 1000000.00, "currency": "EUR",
                              "settlement_date": "2026-06-01", "description": "Paid on completion"}],
        "BC_Acquired_Balances": [{"deal_ref": "EXAMPLE_ACQ-CZ01-2026", "main_account": "EXAMPLE_1241", "book_amount": 800000.00,
                                  "fair_value_adjustment": "", "note": "Balances at 31 May 2026 (last period-end before P6); debit +, credit -"}],
        "BC_Costs": [{"deal_ref": "EXAMPLE_ACQ-CZ01-2026", "kind": "Advisory", "amount": 25000.00, "currency": "EUR",
                      "description": "Transaction advisory fees"}],
        # ... and disposes of EXAMPLE_DK01 on the last day of P12 for 500,000 EUR
        "Business_Disposals": [{"deal_ref": "EXAMPLE_DISP-DK01-2026", "consolidation_group": "EXAMPLE_GRP", "disposed_entity": "EXAMPLE_DK01",
                                "disposal_date": "2026-12-31", "share_disposed_pct": 100, "retained_interest_pct": 0, "proceeds_currency": "EUR",
                                "description": "Sale of Example Danmark ApS, 100%"}],
        "BD_Proceeds": [{"deal_ref": "EXAMPLE_DISP-DK01-2026", "component": "Cash", "amount": 500000.00, "currency": "EUR",
                         "settlement_date": "2026-12-31", "description": "Received on completion"}],
        "Trial_Balance": [{"data_area_id": "EXAMPLE_DE01", "fiscal_year": 2026, "fiscal_period": 1, "main_account": "EXAMPLE_1241",
                           "debit": 125000.00, "credit": 0, "currency": "EUR", "description": "Bank current accounts", "partner_data_area_id": "",
                           "amount_basis": "Period-end balance", "dim_cost_center": ""},
                          {"data_area_id": "EXAMPLE_DE01", "fiscal_year": 2026, "fiscal_period": 1, "main_account": "EXAMPLE_2212",
                           "debit": 0, "credit": 40000.00, "currency": "EUR", "description": "Trade payables - intercompany",
                           "partner_data_area_id": "EXAMPLE_FR01", "amount_basis": "Period-end balance", "dim_cost_center": ""},
                          {"data_area_id": "EXAMPLE_DE01", "fiscal_year": 2026, "fiscal_period": 1, "main_account": "EXAMPLE_6110",
                           "debit": 0, "credit": 85000.00, "currency": "EUR", "description": "Salaries and wages (shown as a credit only to balance this 3-row example)",
                           "partner_data_area_id": "", "amount_basis": "Period-end balance", "dim_cost_center": "CC100"}],
    }


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
    widths = {"A": 12, "B": 8, "C": 8, "D": 10, "E": 16, "F": 16, "G": 8, "H": 42, "I": 12, "J": 18, "K": 16, "L": 14, "M": 14}
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
        "Aquila Group example - bulk trial balance file for %s" % period_name(p),
        "Format: konsol Trial Balance Upload (data on the FIRST sheet). Amount basis: %s." % BASIS,
        "%d rows, %d entities, %d currencies. Debits equal credits exactly per entity in its own currency." % (
            len(rows), len(entities), len({r["currency"] for r in rows})),
        "Intercompany rows carry partner_data_area_id; both sides are booked at the group's governed rates (FX_Rates), so pairs match after translation.",
        "Dimension columns: " + ", ".join(dims) + " (blank = no value).",
        "Generated by excel/onboarding/build_workbooks.py; fictional data.",
    ):
        about.append([line])
    about.column_dimensions["A"].width = 140
    wb.save(path)


def build_example():
    os.makedirs(os.path.join(EXAMPLE_DIR, "tb"), exist_ok=True)
    files, summary = build_trial_balances()
    dims = ["dim_business_line", "dim_cost_center", "dim_product_group"]
    for p, rows in files.items():
        path = os.path.join(EXAMPLE_DIR, "tb", "TB_FY%d_P%02d.xlsx" % p)
        write_tb_file(path, rows, p, dims)
        print("wrote %s  (%d rows)" % (os.path.relpath(path, HERE), len(rows)))
    sample = [dict(r, debit=r["debit"] / 100, credit=r["credit"] / 100) for r in files[(2026, 1)] if r["data_area_id"] == "DE01"][:60]
    rows = master_rows(sample)
    rows["Trial_Balance"] = [dict(r, debit=r["debit"] or None, credit=r["credit"] or None) for r in sample]
    path = os.path.join(EXAMPLE_DIR, "Aquila_Group_Master_Data.xlsx")
    intro = (
        "Filled onboarding workbook for the fictional Aquila Group: %d legal entities in %d countries and %d currencies, "
        "a %d-row group chart, %d dimensions, %d reporting hierarchies, a 3-level consolidation tree (root, four regional sub-groups) "
        "with minority (51%%-80%%), joint-venture (50%% proportional) and associate (40%% equity) holdings, governed FX rates and "
        "IAS 21 historical equity rates." % (len(ENT), len({e["country"] for e in ENT.values()}), len(BASE_RATE), len(A),
                                              len(DIMENSIONS), len(HIERARCHIES)),
        "Trial balances are in tb/: TB_FY2025_P12.xlsx holds the opening year-end balances (FY2025 P&L still in its accounts, "
        "which the warehouse closes to 3300 Retained earnings in the FY2025 Closing period), then TB_FY2026_P01..P11, one upload "
        "per month, all on the Period-end balance basis.",
        "Load with: uv run konsol_load.py examples/aquila/Aquila_Group_Master_Data.xlsx --tb-dir examples/aquila/tb -s <frappectl profile>. "
        "Every sheet mirrors a konsol doctype; see README.md.",
        "The Trial_Balance sheet below shows the first 60 rows of DE01 in TB_FY2026_P01.xlsx as a format reference; it is not loaded from here.",
    )
    write_workbook(path, rows, title="Aquila Group - konsolidat onboarding example", intro_lines=intro)
    print("wrote %s" % os.path.relpath(path, HERE))
    # a short check summary
    total = sum(len(v) for v in files.values())
    print("trial balances: %d periods, %d rows, %d entities, all balanced" % (len(files), total, len(ENT)))
    return files


def build_template():
    path = os.path.join(HERE, "Konsolidat_Onboarding_Template.xlsx")
    intro = (
        "Fill this workbook to onboard a group onto konsolidat / konsol: every sheet is one konsol doctype, every column header is "
        "its fieldname (hover a header for help; red = required). Work through the sheets in order; later sheets reference codes "
        "defined on earlier ones.",
        "Trial balances are separate files (one per period, data on the first sheet) in the format on the Trial_Balance sheet. "
        "Start from the last closed year end on the Period-end balance basis, then upload each month.",
        "Load everything with konsol_load.py (frappectl) or sheet by sheet with Frappe Desk > Data Import. See README.md and, for a "
        "complete filled example, examples/aquila/.",
        "Grey italic rows are format examples with EXAMPLE_ codes: delete them before loading (the loader refuses them).",
    )
    write_workbook(path, {}, title="Konsolidat onboarding template", intro_lines=intro, example_rows=template_examples(), input_fill=True)
    print("wrote %s" % os.path.relpath(path, HERE))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("what", nargs="?", choices=("template", "example", "all"), default="all")
    args = ap.parse_args()
    if args.what in ("template", "all"):
        build_template()
    if args.what in ("example", "all"):
        build_example()


if __name__ == "__main__":
    main()
