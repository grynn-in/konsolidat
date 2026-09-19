"""Which sub-section of the consolidation report an account belongs to (konsolidat#185).

The report used to decide this from D365 account-number prefixes — `5` is Cost
of Goods Sold, `6` is Operating Expenses, `7`/`8` is Other Income. An account id
that is not a D365 number, such as ERPNext's `"Cost of Goods Sold - XX"`,
matched none of them and fell through to a section that is not in
`section_order`, so it joined **no subtotal at all**: gross profit and operating
profit came out wrong and nothing failed.

Since konsol#182 the group chart is governed in konsol and each account declares
its own `statement_section` and `sub_section`, reaching the warehouse through
`epm_silver.silver_main_accounts`. So:

  1. **The declaration wins.** If the chart says where an account belongs, that
     is the answer — whatever its id looks like.
  2. **The prefix table is a named fallback.** A chart that has not declared a
     sub-section still produces a report, but every account placed that way is
     returned as a fallback and shown in the report's diagnostics. An account
     silently placed in the wrong subtotal is the defect being fixed; placing it
     silently in the *right* one would be the same mechanism, still unexamined.
  3. **A fallback never invents a section.** Every prefix outcome is inside
     `PNL_SECTION_ORDER` / `BS_SECTION_ORDER`, so a misplaced account is visibly
     in the wrong subtotal rather than invisibly outside all of them.

Pure: no I/O, no ClickHouse, no side effects at import — which is what makes it
testable, since build_consolidation_report.py queries the warehouse as it loads.
Same reason konsol/build_command.py exists.
"""

#: The P&L subtotals the report knows how to total, in order.
PNL_SECTION_ORDER = [
    "Revenue",
    "Cost of Goods Sold",
    "Operating Expenses",
    "Other Income / Expense",
    "Income Tax",
]

#: The balance-sheet subtotals, in order.
BS_SECTION_ORDER = [
    "Current Assets",
    "Non-Current Assets",
    "Current Liabilities",
    "Non-Current Liabilities",
    "Shareholders' Equity",
]

# Fallback only, for a chart that declares no sub_section. Kept as the D365
# ranges they always were; the point of konsolidat#185 is that they are no
# longer the first answer.
_PNL_PREFIXES = [
    ("Revenue", "Revenue", lambda a: True),
    ("Expense", "Cost of Goods Sold", lambda a: a[:1] == "5" or a.startswith("6112")),
    ("Expense", "Operating Expenses", lambda a: a[:1] == "6" and not a.startswith("6112")),
    ("Profit and loss", "Income Tax", lambda a: a.startswith("802")),
    ("Profit and loss", "Other Income / Expense", lambda a: a[:1] in ("7", "8")),
    ("Expense", "Other Income / Expense", lambda a: a[:1] in ("7", "8")),
]

_BS_PREFIXES = [
    ("Asset", "Current Assets",
     lambda a: a[:2] in ("11", "12", "13", "14") and a[:3] not in ("120", "134")),
    ("Asset", "Non-Current Assets",
     lambda a: a[:2] in ("15", "16", "17", "18") or a[:3] in ("120", "134")),
    ("Balance sheet", "Current Assets", lambda a: a[:1] == "1"),
    ("Balance sheet", "Non-Current Assets", lambda a: a[:1] != "1"),
    ("Liability", "Current Liabilities", lambda a: a[:2] in ("20", "21", "22", "23")),
    ("Liability", "Non-Current Liabilities",
     lambda a: a[:2] in ("24", "25", "26", "27", "28", "29")),
    ("Equity", "Shareholders' Equity", lambda a: True),
]

#: Where an account goes when neither its chart nor the prefixes place it.
#: Never outside section_order — see rule 3. An expense the report cannot
#: identify is an operating expense by default, which is the assumption that
#: distorts the fewest subtotals, and it is reported as a fallback either way.
_PNL_LAST_RESORT = {
    "Revenue": "Revenue",
    "Expense": "Operating Expenses",
    "Profit and loss": "Other Income / Expense",
}
_BS_LAST_RESORT = {
    "Asset": "Current Assets",
    "Liability": "Current Liabilities",
    "Equity": "Shareholders' Equity",
    "Balance sheet": "Current Assets",
}


def _from_prefixes(table, account_type_name, main_account, last_resort, order):
    account = main_account or ""
    for atype, subsection, matches in table:
        if account_type_name == atype and matches(account):
            return subsection
    fallback = last_resort.get(account_type_name)
    if fallback:
        return fallback
    # An account_type_name the report has never seen. Put it somewhere it will
    # at least be totalled and shown, rather than outside every subtotal.
    return order[-1]


def _declared(declared):
    """A declaration is a non-blank string; whitespace is not a declaration."""
    return (declared or "").strip()


def classify(account_type_name, main_account, declared=""):
    """The P&L sub-section for an account, and whether it fell back.

    Returns ``(sub_section, fell_back)``. ``fell_back`` is True when the chart
    declared nothing and the prefix table decided — the caller must surface
    those accounts (konsolidat#185).
    """
    text = _declared(declared)
    if text:
        return text, False
    return _from_prefixes(_PNL_PREFIXES, account_type_name, main_account,
                          _PNL_LAST_RESORT, PNL_SECTION_ORDER), True


def classify_bs(account_type_name, main_account, declared=""):
    """The balance-sheet sub-section for an account, and whether it fell back."""
    text = _declared(declared)
    if text:
        return text, False
    return _from_prefixes(_BS_PREFIXES, account_type_name, main_account,
                          _BS_LAST_RESORT, BS_SECTION_ORDER), True
