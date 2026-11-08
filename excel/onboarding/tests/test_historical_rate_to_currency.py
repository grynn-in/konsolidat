"""konsol#374 (b): a Historical Equity Rate carries its presentation currency (`to_currency`, required).
The template, the aquila-bike generator and the template's example rows must all supply it, or the loader's
create is refused ("To Currency is required"), as happened on demo-ext on 8 Nov 2026."""
import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

import build_aquila_bike as bab  # noqa: E402
import build_workbooks as bw  # noqa: E402
from konsol_template import BY_NAME  # noqa: E402


class HistoricalRateToCurrency(unittest.TestCase):
    def test_template_requires_to_currency(self):
        cols = {c.name: c for c in BY_NAME["Historical_Equity_Rates"].cols}
        self.assertIn("to_currency", cols)
        self.assertTrue(cols["to_currency"].required)

    def test_aquila_bike_rates_convert_into_the_group_currency(self):
        rows = bab.historical_rate_rows()
        self.assertTrue(rows)
        for r in rows:
            self.assertEqual(r.get("to_currency"), bab.GROUP_CUR, r)

    def test_example_rates_convert_into_the_group_currency(self):
        rows = bw.historical_rate_rows()
        self.assertTrue(rows)
        for r in rows:
            self.assertEqual(r.get("to_currency"), bw.GROUP_CUR, r)

    def test_template_example_rows_carry_to_currency(self):
        ex = bw.template_examples()
        groups = {g["consolidation_group"]: g for g in ex["Consolidation_Groups"] if not g.get("data_area_id")}
        for r in ex["Historical_Equity_Rates"]:
            self.assertEqual(r.get("to_currency"), groups[r["consolidation_group"]]["reporting_currency"], r)


if __name__ == "__main__":
    unittest.main()
