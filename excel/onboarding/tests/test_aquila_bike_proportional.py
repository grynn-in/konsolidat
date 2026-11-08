"""konsol#117 pair 3 review finding G: the replica treats a `proportional` entity (IFRS 11 joint operation) as the
warehouse does: the operator's share of each line, no NCI, and an IC elimination at least(share_a, share_b).
aquila-bike has no proportional entity, so expected.json is unchanged (test_aquila_bike_determinism)."""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import aquila_bike_offline as ab  # noqa: E402

P = (2026, 1)


class TinyGroup(ab.Offline):
    """P (100% full) owns J (50% proportional); no inputs.json, one P&L account."""

    def __init__(self, j_method="proportional"):
        self.group, self.gcur = "G", "EUR"
        self.ent = {"P": {"currency": "EUR"}, "J": {"currency": "EUR"}}
        self.chart = {"RE": {"flags": "RE"}, "4000": {"flags": "PNL"}}
        self.policy = {"nci_account": "NCI"}
        self.links = [{"entity": "P", "owner": "", "pct": 100, "method": "full", "since": "2020-01-01"},
                      {"entity": "J", "owner": "P", "pct": 50, "method": j_method, "since": "2020-01-01"}]
        self.declarations = []
        self.dsp = {"entity": "", "date": "2099-01-01"}
        self._resolved = {}

    def period_date(self, p):
        import datetime as dt
        return dt.date(2026, 1, 31)

    def fx_method(self, a): return "average"
    def closing(self, cur, p): return 1.0
    def average(self, cur, p): return 1.0
    def is_pnl(self, a): return True
    def is_bs(self, a): return False
    def is_equity(self, a): return False


class Proportional(unittest.TestCase):
    def rows(self, o):
        mov = {"J": {P: {("4000", ""): (100000, "x", False)}}}      # J profit 1,000.00
        return o.translate(mov)

    def test_group_amount_is_the_operator_share_and_nci_zero(self):
        o = TinyGroup()
        (r,) = self.rows(o)
        self.assertAlmostEqual(r["group"], 500.0)
        self.assertEqual(r["nci"], 0.0)

    def test_no_nci_attribution_for_proportional(self):
        o = TinyGroup()
        self.assertEqual(o.nci_attribution(self.rows(o), {}), [])

    def test_full_method_still_group_100_and_nci_complement(self):
        o = TinyGroup("full")
        (r,) = self.rows(o)
        self.assertAlmostEqual(r["group"], 1000.0)
        self.assertAlmostEqual(r["nci"], 500.0)

    def test_ic_factor_is_least_of_the_two_shares(self):
        o = TinyGroup()
        self.assertEqual(o.ic_share("P", P), 1.0)
        self.assertEqual(o.ic_share("J", P), 0.5)
        self.assertEqual(o.ic_factor("P", "J", P), 0.5)
        self.assertEqual(o.ic_factor("P", "P", P), 1.0)


if __name__ == "__main__":
    unittest.main()
