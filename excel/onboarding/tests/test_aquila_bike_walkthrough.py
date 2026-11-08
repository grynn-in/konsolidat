"""konsol#117 pair 2, K5c: the aquila-bike walkthrough workbook follows the new rules (konsolidat#204 option (a), ABJV).

The builder (build_aquila_bike_walkthrough.py) is run on the committed model/expected.json into a temp file.
Its check cells are Excel formulas; build() returns the same checks computed in Python (`python` values) and the
cells' addresses (`cells`). The slow test recalculates the workbook in LibreOffice and reads every check cell.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

import openpyxl

HERE = os.path.dirname(os.path.abspath(__file__))
ONB = os.path.dirname(HERE)
sys.path.insert(0, ONB)

import build_aquila_bike_walkthrough as bw  # noqa: E402

TMP = tempfile.mkdtemp(prefix="walkthrough_")
OUT = os.path.join(TMP, "Aquila_Bike_Walkthrough.xlsx")


def tearDownModule():
    shutil.rmtree(TMP, ignore_errors=True)


class Walkthrough(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        bw.OUT = OUT
        cls.result = bw.build()
        cls.wb = openpyxl.load_workbook(OUT)
        with open(os.path.join(ONB, "examples", "aquila-bike", "model", "expected.json")) as f:
            cls.exp = json.load(f)

    def test_the_two_new_sheets_exist(self):
        self.assertIn("NCI attribution", self.wb.sheetnames)
        self.assertIn("Joint venture ABJV", self.wb.sheetnames)

    def test_statements_shows_one_view(self):
        ws = self.wb["Statements"]
        texts = [str(c.value) for row in ws.iter_rows() for c in row if isinstance(c.value, str)]
        self.assertFalse([t for t in texts if "IFRS view" in t or "IFRS 10 view" in t or "tool view" in t.lower()])
        self.assertTrue([t for t in texts if t.startswith("NCI: how the tool computes it")])

    def test_no_nci_leg_left_on_the_ic_sheet(self):
        ws = self.wb["IC"]
        heads = [str(c.value) for c in ws[1]]
        self.assertFalse([h for h in heads if "NCI" in h])

    def test_opening_journal_rows_come_from_expected_json(self):
        ws = self.wb["Topside"]
        rows = {(r[2].value, r[3].value): r[6].value for r in ws.iter_rows(min_row=2) if r[2].value}
        for x in self.exp["topside"]:
            self.assertAlmostEqual(rows[(x["entity"], x["account"])], x["amount"], places=2)
        self.assertAlmostEqual(rows[("ABSE", "3300")], 216000.0, places=2)
        self.assertAlmostEqual(rows[("ABSE", "3700")], -1197277.20, places=2)

    def test_python_side_checks_are_all_zero(self):
        py = self.result["python"]
        self.assertTrue(py)
        for label, value in py.items():
            self.assertLess(abs(value), 0.005, "%s = %r" % (label, value))

    def test_nci_closing_is_the_figure_in_the_pr(self):
        self.assertAlmostEqual(self.result["figures"]["nci_closing_2024_12"], 2752660.58, places=2)
        self.assertAlmostEqual(self.result["figures"]["nci_opening"], 1197277.20, places=2)


class TwelveLines(unittest.TestCase):
    def test_readme_section_is_the_script_output(self):
        import aquila_bike_pl as pl
        with open(pl.EXPECTED) as f:
            exp = json.load(f)
        tables = pl.columns(exp)
        pl.check(tables)
        self.assertEqual(len(pl.LINES), 12)
        text = pl.markdown(tables, 1000, pl.notes(tables, exp))
        with open(os.path.join(ONB, "examples", "aquila-bike", "README.md")) as f:
            readme = f.read()
        self.assertIn(text.strip(), readme)


@unittest.skipUnless(shutil.which("soffice"), "LibreOffice not installed")
class Recalculated(unittest.TestCase):
    """Every check cell the builder wrote reads zero after LibreOffice recalculates the formulas."""

    @classmethod
    def setUpClass(cls):
        bw.OUT = OUT
        cls.result = bw.build()
        out = os.path.join(TMP, "recalc")
        os.makedirs(out, exist_ok=True)
        subprocess.run(["soffice", "--headless", "--convert-to", "xlsx", "--outdir", out, OUT], check=True,
                       capture_output=True, timeout=1500)
        cls.wb = openpyxl.load_workbook(os.path.join(out, os.path.basename(OUT)), data_only=True)

    def test_check_cells_are_zero(self):
        self.assertTrue(self.result["cells"])
        for label, sheet, ref in self.result["cells"]:
            v = self.wb[sheet][ref].value
            self.assertIsNotNone(v, "%s %s!%s empty" % (label, sheet, ref))
            self.assertLess(abs(v), 0.005, "%s: %s!%s = %r" % (label, sheet, ref, v))

    def test_no_error_cell(self):
        bad = []
        for ws in self.wb.worksheets:
            for row in ws.iter_rows():
                for c in row:
                    if isinstance(c.value, str) and c.value.startswith("#") and c.value[1:4].isupper():
                        bad.append((ws.title, c.coordinate, c.value))
        self.assertEqual(bad[:5], [])


if __name__ == "__main__":
    unittest.main()
