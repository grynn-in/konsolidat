"""konsolidat#185: the consolidation report must read the chart, not guess from
account numbers.

`build_consolidation_report.py` chose each P&L and balance-sheet sub-section
from D365 account-number prefixes — `5` is Cost of Goods Sold, `6` is Operating
Expenses, `7`/`8` is Other Income. An account id that is not a D365 number, such
as ERPNext's `"Cost of Goods Sold - XX"`, matched none of them and fell through
to a section that is not in `section_order`. It then landed outside COGS, OpEx
and every subtotal: **gross profit and operating profit came out wrong and
nothing failed.** konsolidat#184 fixed the same shape for revenue.

Since konsol#182 the group chart is governed in konsol and carries a declared
`statement_section` / `sub_section` per account, reaching the warehouse through
`epm_silver.silver_main_accounts`. The declaration is the answer; the prefix
table is a fallback for a chart that has not declared one, and a fallback that
is **named** — every account that uses it is reported, because an account
silently placed in the wrong subtotal is exactly this defect.

The classification is a pure function in `scripts/report_subsections.py` so it
can be tested here: `build_consolidation_report.py` queries ClickHouse at import
time and cannot be imported in a test. Same reason `konsol/build_command.py`
exists.

`python -m unittest -v tests.test_report_subsections`
"""
import os
import sys
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "scripts"))


class DeclarationWins(unittest.TestCase):
    """Rule 1: if the chart declares a sub-section, that is the answer."""

    def test_declared_subsection_beats_the_prefix_rule(self):
        from report_subsections import classify
        # "5..." would be Cost of Goods Sold by prefix; the chart says otherwise.
        sub, fell_back = classify("Expense", "5100", declared="Operating Expenses")
        self.assertEqual(sub, "Operating Expenses")
        self.assertFalse(fell_back)

    def test_a_non_numeric_account_is_classified_from_its_declaration(self):
        """The reported defect: an ERPNext account id matches no prefix."""
        from report_subsections import classify
        sub, fell_back = classify("Expense", "Cost of Goods Sold - XX",
                                  declared="Cost of Goods Sold")
        self.assertEqual(sub, "Cost of Goods Sold")
        self.assertFalse(fell_back)

    def test_declaration_is_trimmed_and_blank_is_not_a_declaration(self):
        from report_subsections import classify
        self.assertEqual(classify("Expense", "5100", declared="  Operating Expenses ")[0],
                         "Operating Expenses")
        self.assertTrue(classify("Expense", "5100", declared="   ")[1],
                        "whitespace was treated as a declaration")


class FallbackIsNamed(unittest.TestCase):
    """Rule 2: an undeclared account may still be placed, but never silently."""

    def test_undeclared_account_falls_back_to_the_prefix_table(self):
        from report_subsections import classify
        sub, fell_back = classify("Expense", "5100", declared="")
        self.assertEqual(sub, "Cost of Goods Sold")
        self.assertTrue(fell_back, "the fallback was not reported")

    def test_an_undeclared_non_numeric_expense_still_reaches_a_real_subtotal(self):
        """It must not land outside section_order, which is the actual harm."""
        from report_subsections import classify, PNL_SECTION_ORDER
        sub, fell_back = classify("Expense", "Cost of Goods Sold - XX", declared="")
        self.assertTrue(fell_back)
        self.assertIn(sub, PNL_SECTION_ORDER,
                      f"{sub!r} is outside section_order, so it joins no subtotal")

    def test_every_pnl_prefix_outcome_is_inside_section_order(self):
        """No prefix rule may produce a section the report cannot total."""
        from report_subsections import classify, PNL_SECTION_ORDER
        for atype in ("Expense", "Revenue", "Profit and loss"):
            for account in ("5100", "6112", "6200", "7000", "8020", "802", "ZZ-not-a-number"):
                sub, _ = classify(atype, account, declared="")
                self.assertIn(sub, PNL_SECTION_ORDER,
                              f"{atype}/{account} -> {sub!r} is outside section_order")

    def test_balance_sheet_falls_back_inside_its_own_order(self):
        from report_subsections import classify_bs, BS_SECTION_ORDER
        for atype in ("Asset", "Liability", "Equity", "Balance sheet"):
            for account in ("1100", "1500", "2000", "2400", "3000", "ZZ-not-a-number"):
                sub, _ = classify_bs(atype, account, declared="")
                self.assertIn(sub, BS_SECTION_ORDER,
                              f"{atype}/{account} -> {sub!r} is outside section_order")


class TheReportUsesIt(unittest.TestCase):
    """Static: build_consolidation_report.py must read the declaration and
    surface the fallbacks, rather than keeping its own prefix tables."""

    def setUp(self):
        with open(os.path.join(ROOT, "scripts", "build_consolidation_report.py"),
                  encoding="utf-8") as f:
            self.src = f.read()

    def test_the_report_imports_the_shared_classifier(self):
        self.assertTrue("report_subsections" in self.src,
                        "the report still carries its own copy of the rule")

    def test_the_report_reads_the_declared_sub_section(self):
        self.assertTrue("sub_section" in self.src, "sub_section is never read")
        self.assertTrue("silver_main_accounts" in self.src,
                        "nothing queries the governed chart")

    def test_the_old_prefix_tables_are_gone_from_the_report(self):
        """Two copies of the rule is how they drift apart."""
        for dead in ("PNL_SUBSECTIONS = [", "BS_SUBSECTIONS = ["):
            self.assertTrue(dead not in self.src,
                            f"{dead.strip(' =[')} still lives in the report")

    def test_undeclared_accounts_reach_the_diagnostics_sheet(self):
        """The issue asks for this explicitly: an account placed by prefix is a
        chart that has not been declared, and the reader must be told.

        Asserted on the diagnostics builder's own body, not on the file: the
        collector's NAME appears the moment it is declared, so a whole-file
        search would pass while nothing displayed it."""
        seg = self.src[self.src.index("def build_diagnostics_sheet"):]
        seg = seg[:seg.index("\ndef ")] if "\ndef " in seg else seg
        self.assertIn("UNDECLARED_ACCOUNTS", seg,
                      "the diagnostics sheet never reads the collector")
        self.assertIn("WARN", seg)

    def test_the_collector_is_actually_filled(self):
        """And the other end: _discover_sections must append to it."""
        seg = self.src[self.src.index("def _discover_sections"):]
        seg = seg[:seg.index("\ndef ")]
        self.assertIn("UNDECLARED_ACCOUNTS.append", seg,
                      "nothing records an account placed by prefix")
        self.assertIn("fell_back", seg, "the fallback flag is ignored")


if __name__ == "__main__":
    unittest.main()
