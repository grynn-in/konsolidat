"""konsolidat#335 X0b: the onboarding template, loader and examples carry the Consolidation Group root column
exit_gain_loss_account (the account an Ownership Period end with no Business Disposal posts to)."""
import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
sys.path.insert(0, HERE)

import build_mini  # noqa: E402
import build_aquila_bike  # noqa: E402
from konsol_template import BY_NAME  # noqa: E402

COL = "exit_gain_loss_account"


class ExitGainLossAccount(unittest.TestCase):
    def test_template_declares_the_column_optional_with_help(self):
        sheet = BY_NAME["Consolidation_Groups"]
        col = [c for c in sheet.columns if c.name == COL]
        self.assertEqual(len(col), 1)
        self.assertFalse(col[0].required)
        self.assertIn("without a Business Disposal", col[0].help)
        self.assertIn("konsolidat#335", col[0].help)

    def test_loader_maps_the_column_to_the_doc(self):
        from test_konsol_load_graph import FakeSite, run_loader
        site = FakeSite()
        row = {"consolidation_group": "G", "is_group": 1, COL: "6735"}
        run_loader(site, {"Consolidation_Groups": [row]})
        creates = [w for w in site.writes if w[0] == "create" and w[1] == "Consolidation Group"]
        self.assertEqual(len(creates), 1)
        self.assertEqual(creates[0][3].get(COL), "6735")

    def test_examples_declare_it_blank(self):
        # no bare exits: Mini's DSP exit is a Business Disposal, aquila has no exit
        self.assertEqual(build_mini.POLICY[COL], "")
        self.assertEqual(build_aquila_bike.POLICY[COL], "")


if __name__ == "__main__":
    unittest.main()
