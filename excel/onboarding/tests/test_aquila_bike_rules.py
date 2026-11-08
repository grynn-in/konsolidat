"""konsol#117 pair 2, K5b: the Aquila Bike replica follows the new consolidation rules (konsolidat#204 option (a)).

No site, no ClickHouse: the replica (aquila_bike_offline.py) is run on model/inputs.json and its layers are
checked against the rules the dbt models state:
  K1 group_amount = translated_amount for a full subsidiary;
  K2 gold_nci_attribution_journal (result share + CTA share to the NCI line);
  K3 gold_ic_eliminations (in full, no NCI leg);
  pair 1 ownership_resolution (paths add; a declaration decides a multi-path entity).
"""
import json
import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ONB = os.path.dirname(HERE)
sys.path.insert(0, ONB)

import aquila_bike_offline as ab  # noqa: E402

TOL = 1e-6


class Rules(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.o = ab.Offline(ab.load_inputs()).run()

    # (a) ownership resolution --------------------------------------------------------------------
    def test_abjv_is_equity_at_60_from_the_declaration(self):
        r = self.o.resolve("ABJV", (2024, 6))
        self.assertAlmostEqual(r["eff"], 0.6, places=9)
        self.assertEqual(r["method"], "equity")
        self.assertEqual(r["source"], "declared")

    def test_abse_is_full_at_70_from_its_link(self):
        r = self.o.resolve("ABSE", (2024, 6))
        self.assertAlmostEqual(r["eff"], 0.7, places=9)
        self.assertEqual(r["method"], "full")
        self.assertEqual(r["source"], "link")

    def test_an_undeclared_multi_path_entity_resolves_to_none(self):
        d = ab.load_inputs()
        d["declarations"] = []
        r = ab.Offline(d).resolve("ABJV", (2024, 6))
        self.assertEqual((r["method"], r["source"]), ("none", "undeclared"))

    # (b) the NCI attribution journal -------------------------------------------------------------
    def test_attribution_journal_nets_to_zero_and_its_nci_line_is_the_minority_share(self):
        p = (2024, 6)
        lines = [l for l in self.o.nci_lines if l["entity"] == "ABSE" and l["period"] == p]
        self.assertTrue(lines)
        self.assertLess(abs(sum(l["amount"] for l in lines)), TOL)
        self.assertEqual({l["journal"] for l in lines}, {"NCI-AQBIKE-ABSE-2024-P6"})
        self.assertEqual({l["type"] for l in lines}, {"nci_attribution"})
        pnl = sum(r["translated"] for r in self.o.rows
                  if r["entity"] == "ABSE" and r["period"] == p and self.o.is_pnl(r["account"]) and not r["is_close"])
        cta = self.o.cta_by[("ABSE", p)]
        nci = [l for l in lines if l["account"] == "3700"]
        self.assertEqual(len(nci), 1)
        self.assertAlmostEqual(nci[0]["amount"], 0.3 * (pnl + cta), places=6)
        self.assertAlmostEqual(next(l["amount"] for l in lines if l["account"] == "3300"), -0.3 * pnl, places=6)
        self.assertAlmostEqual(next(l["amount"] for l in lines if l["account"] == "CTA"), -0.3 * cta, places=6)

    def test_year_end_close_rows_are_not_attributed(self):
        lines = [l for l in self.o.nci_lines if l["entity"] == "ABSE" and l["period"] == (2023, 13)]
        self.assertEqual([l for l in lines if l["account"] == "3300"], [])

    def test_only_a_partly_owned_full_subsidiary_has_an_attribution_journal(self):
        self.assertEqual({l["entity"] for l in self.o.nci_lines}, {"ABSE"})

    # (c) intercompany in full --------------------------------------------------------------------
    def test_abse_ic_pair_with_abh_is_eliminated_in_full(self):
        """Both legs of a matched pair are the whole matched amount (a balance pair posts the change since its
        previous row, so its legs are summed to date)."""
        seen = 0
        for r in self.o.recon:
            if {r["entity_a"], r["entity_b"]} != {"ABSE", "ABH"} or r["matched"] < 1:
                continue
            pair = "IC:%s/%s" % (r["account_a"], r["account_b"])
            legs = [e for e in self.o.elims if e["kind"] == "matched" and e["pair"] == pair
                    and (e["entity_a"], e["entity_b"]) == (r["entity_a"], r["entity_b"])
                    and (e["period"] == r["period"] if r["basis"] == "movement" else e["period"] <= r["period"])]
            on_a = sum(e["amount"] for e in legs if e["account"] == r["account_a"])
            on_b = sum(e["amount"] for e in legs if e["account"] == r["account_b"])
            self.assertAlmostEqual(abs(on_a), r["matched"], places=4, msg=r)
            self.assertAlmostEqual(abs(on_b), r["matched"], places=4, msg=r)
            seen += 1
        self.assertGreater(seen, 0)

    def test_no_nci_leg_in_the_eliminations(self):
        for e in self.o.elims:
            self.assertNotEqual(e["kind"], "nci")
            self.assertNotEqual(e["type"], "ic_elimination_nci")
            self.assertNotEqual(e["account"], "3700")

    # (d) group = translated ----------------------------------------------------------------------
    def test_group_amount_equals_translated_for_every_abse_row_of_expected_json(self):
        with open(os.path.join(ab.MODEL_DIR, "expected.json")) as f:
            exp = json.load(f)
        rows = [r for r in exp["translation"] if r["entity"] == "ABSE"]
        self.assertTrue(rows)
        for r in rows:
            self.assertAlmostEqual(r["group"], r["translated"], places=9, msg=r)
            self.assertAlmostEqual(r["nci"], r["translated"] * 0.3, places=6, msg=r)

    # (e) the holders carry their stake ----------------------------------------------------------------
    def test_holders_carry_30pct_of_abjv_opening_equity_and_their_pnl_is_unchanged(self):
        d = ab.load_inputs()
        bal = {}
        for e, y, p, a, partner, c in d["tb_cents"]:
            bal[(e, (y, p), a)] = bal.get((e, (y, p), a), 0) + c
        equity = -(bal[("ABJV", (2024, 1), "3100")] + bal[("ABJV", (2024, 1), "3200")])
        self.assertGreater(equity, 0)
        for holder in ("ABDE", "ABFR"):
            self.assertEqual(bal.get((holder, (2023, 12), "1142"), 0), 0)
            self.assertEqual(bal[(holder, (2024, 1), "1142")], round(equity * 0.3), holder)
            self.assertEqual(bal[(holder, (2024, 12), "1142")], round(equity * 0.3), holder)
        # P&L as at the previous commit (before the swap), kept as a fixture of the unchanged figures
        with open(os.path.join(HERE, "holder_pnl_before_swap.json")) as f:
            before = json.load(f)
        for holder in ("ABDE", "ABFR"):
            for p in ((2024, 1), (2024, 6), (2024, 12)):
                pnl = sum(c for (e, y, per, a, partner, c) in d["tb_cents"] if e == holder and (y, per) == p and a[0] in "45678")
                self.assertEqual(pnl, before["%s-%d-%d" % (holder, *p)])
            self.assertEqual(bal[(holder, (2024, 12), "3300")], before["%s-3300" % holder])

    # whole example -------------------------------------------------------------------------------
    def test_every_period_nets_to_zero(self):
        _periods, _pnl, _bs, check = self.o.statements()
        for p, v in check.items():
            self.assertLess(abs(v), 0.01, p)

    def test_nci_at_closing_is_30pct_of_abse_net_assets(self):
        _periods, _pnl, bs, _check = self.o.statements()
        closing = (2024, 12)
        nci = -bs[closing].get("3700", 0.0)
        net_assets = sum(r["translated"] for r in self.o.rows
                          if r["entity"] == "ABSE" and self.o.is_bs(r["account"]) and not self.o.is_equity(r["account"]))
        self.assertAlmostEqual(nci, 0.3 * net_assets, delta=0.05)

    def test_abjv_pickup_is_60pct_of_its_result(self):
        p = (2024, 6)
        net = sum(c for (a, _), (c, *_r) in self.o.mov["ABJV"][p].items() if self.o.is_pnl(a)) / 100.0
        inc = [l for l in self.o.eq_lines if l["entity"] == "ABJV" and l["period"] == p and l["account"] == "EQ_INCOME"]
        self.assertEqual(len(inc), 1)
        self.assertAlmostEqual(inc[0]["amount"], 0.6 * net, places=6)

    def test_associate_close_rows_post_no_pickup(self):
        self.assertEqual([l for l in self.o.eq_lines if l["period"] == (2023, 13)], [])


if __name__ == "__main__":
    unittest.main()
