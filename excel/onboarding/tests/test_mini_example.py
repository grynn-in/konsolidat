"""The Mini Group example: its books balance, HOLD's investments tie to the share capital of what it holds,
the opening journal nets to zero, and the README's stated group totals are the sums the books give."""
import os
import re
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

import build_mini  # noqa: E402

README = os.path.join(os.path.dirname(HERE), "examples", "mini", "README.md")
ENTITIES = ("HOLD", "SVC", "PRT", "DSP", "ACQ")
IN_GROUP_AT_CLOSE = ("HOLD", "SVC", "PRT", "ACQ")


def readme_number(label):
    for line in open(README, encoding="utf-8"):
        if line.startswith("| " + label) or line.startswith("| **" + label):
            cell = [c.strip() for c in line.strip().strip("|").split("|")][1]
            return int(re.sub(r"[^\d]", "", cell))
    raise AssertionError("README has no table row starting %r" % label)


class MiniExample(unittest.TestCase):
    def test_five_entities(self):
        self.assertEqual(set(build_mini.ENTITIES), set(ENTITIES))

    def test_books_balance_per_entity_period(self):
        for entity in ENTITIES:
            for period in ("START", "ACT", "CLS"):
                self.assertEqual(sum(build_mini.BOOKS[entity][period].values()), 0, (entity, period))
        build_mini.check_books()

    def test_hold_investments_at_start_are_the_share_capital_it_holds(self):
        held = sum(-build_mini.BOOKS[e]["START"][3100] for e in ("DSP", "SVC", "PRT"))
        self.assertEqual(build_mini.BOOKS["HOLD"]["START"][1300], held)

    def test_opening_journal_nets_to_zero_and_eliminates_each_holding(self):
        rows = build_mini.master_rows([])
        lines = rows["CJ_Lines"]
        self.assertEqual(sum(float(l["debit_amount"] or 0) - float(l["credit_amount"] or 0) for l in lines), 0)
        for e in ("DSP", "SVC", "PRT"):
            self.assertEqual(sum(float(l["debit_amount"] or 0) for l in lines
                                 if l["data_area_id"] == e and l["main_account"] == "3100"),
                             -build_mini.BOOKS[e]["START"][3100], e)

    def test_ownership_and_deals_run_through_hold(self):
        rows = build_mini.master_rows([])
        owners = {r["data_area_id"]: r["owner_entity"] for r in rows["Ownership_Periods"]}
        self.assertEqual(owners, {"HOLD": "", "DSP": "HOLD", "SVC": "HOLD", "PRT": "HOLD"})
        self.assertEqual(rows["Business_Combinations"][0]["acquirer_entity"], "HOLD")
        self.assertEqual(rows["Business_Disposals"][0]["disposer_entity"], "HOLD")

    def test_readme_group_cash_at_close_is_the_sum_of_the_books(self):
        cash = sum(build_mini.BOOKS[e]["CLS"].get(1100, 0) for e in IN_GROUP_AT_CLOSE)
        self.assertEqual(readme_number("Group cash at Close"), cash)

    def test_readme_owners_equity_at_close_is_the_net_assets_of_the_books(self):
        net = 0
        for e in IN_GROUP_AT_CLOSE:
            net += sum(v for a, v in build_mini.BOOKS[e]["CLS"].items() if a in (1100, 1200, 1210, 1600, 2100))
        acq = build_mini.BOOKS["ACQ"]["START"]
        goodwill = build_mini.CONSIDERATION - (-(acq[3100] + acq[3300]) + build_mini.FVA)
        net += goodwill + build_mini.FVA
        self.assertEqual(readme_number("Owners' equity at Close"), net)

    def test_group_declares_whole_period_and_the_disposal_is_mid_period(self):
        """konsolidat#171 2c: the example declares its partial-period treatment, and its disposal is a mid-period deal
        (DSP 2025-12-30, in the Regular period that ends 2025-12-31), so the declaration is what the build reads."""
        self.assertEqual(build_mini.POLICY["partial_period_treatment"], "Whole period")
        regular = [p for p in build_mini.PERIODS if p[2] == "Regular" and p[4] <= build_mini.DSP_DATE <= p[5]]
        self.assertEqual(len(regular), 1)
        self.assertLess(build_mini.DSP_DATE, regular[0][5])


if __name__ == "__main__":
    unittest.main()
