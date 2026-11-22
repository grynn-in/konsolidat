"""konsolidat#335 (task X22, problem B): the integration fixture that seeds a
bare ownership end declares the account its exit journal posts to.

tests/integration/fixtures/ic_decisions.sql ends two links of group ZZGRP with
no Business Disposal and no successor: ZZH (to 2095-02-28, "disposed") and the
sub-group ZZSUB (to 2095-02-28, "sold", taking ZZS out of ZZGRP). Both carry
balance-sheet balances in P1 (ZZH ZZ2010 -400, ZZS ZZ2010 -300). Under #335
option A (Deepak Pai, 14 Nov 2026) such an end is an ownership exit and the
group derecognises what it carried through gold_ownership_exit_journal, whose
balancing line posts to the root's exit_gain_loss_account. With none declared
the journal posts nothing and assert_exit_accounts_declared (ERROR) names the
group: CI's full-build job failed exactly there
(test_ic_decisions_12_to_14_on_data, PASS=185 WARN=2 ERROR=1). The assertion
is right; the fixture predates #335 and must declare the account.

What this pins, without a database: every link the fixture ends before
2149-06-06 with no successor row and no seeded Business Disposal belongs to a
group whose root row (data_area_id = '') declares exit_gain_loss_account, and
that account is a Published posting leaf of the fixture's chart on the profit
and loss (assert_exit_accounts_declared's chart rule; a gain or loss is P&L).

Plain unittest, no third-party imports:
`python -m unittest -v tests.test_ic_decisions_exit_account`.
"""
import ast
import datetime
import os
import re
import unittest

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FIXTURE = os.path.join(PROJECT_ROOT, "tests", "integration", "fixtures", "ic_decisions.sql")
OPEN_END = "2149-06-06"

INSERT_RE = re.compile(r"^INSERT INTO (\S+) \(([^)]*)\) VALUES (.*);\s*$", re.M)


def _rows(text, table):
    """The rows of every column-named INSERT into `table`, as dicts."""
    out = []
    for name, cols, values in INSERT_RE.findall(text):
        if name != table:
            continue
        keys = [c.strip() for c in cols.split(",")]
        tuples = ast.literal_eval("[" + values + "]")
        out.extend(dict(zip(keys, t)) for t in tuples)
    return out


def _next_day(d):
    return (datetime.date.fromisoformat(d) + datetime.timedelta(days=1)).isoformat()


class IcDecisionsExitAccount(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with open(FIXTURE) as f:
            cls.text = f.read()

    def bare_ends(self):
        periods = _rows(self.text, "epm_staging.ownership_periods")
        self.assertTrue(periods, "the fixture seeds no ownership_periods rows")
        self.assertNotIn("epm_staging.business_disposals", self.text,
                         "the fixture now seeds a Business Disposal: revisit which ends are bare")
        link = lambda r: (r["consolidation_group"], r["data_area_id"], r["owner_group"], r["owner_data_area_id"])
        starts = {(link(r), r["effective_date"]) for r in periods}
        return [r for r in periods
                if r["end_date"] != OPEN_END and (link(r), _next_day(r["end_date"])) not in starts]

    def test_the_fixture_seeds_bare_ends(self):
        ends = {(r["consolidation_group"], r["data_area_id"]) for r in self.bare_ends()}
        self.assertEqual(ends, {("ZZGRP", "ZZH"), ("ZZSUB", "")})

    def test_every_group_with_a_bare_end_declares_its_exit_account(self):
        ancestry = _rows(self.text, "epm_staging.consolidation_ancestry")
        groups = {}
        for r in self.bare_ends():
            for a in ancestry:
                if (a["link_group"], a["link_data_area_id"]) == (r["consolidation_group"], r["data_area_id"]):
                    groups.setdefault(a["consolidation_group"], set()).add(a["data_area_id"])
        self.assertEqual(set(groups), {"ZZGRP"})

        roots = {r["consolidation_group"]: r for r in _rows(self.text, "epm_gold.consolidation_groups")
                 if r["data_area_id"] == ""}
        chart = {r["main_account"]: r for r in _rows(self.text, "epm_staging.main_accounts")}
        for group, entities in sorted(groups.items()):
            self.assertIn(group, roots, f"{group} has no root row")
            account = roots[group].get("exit_gain_loss_account", "")
            self.assertNotEqual(
                account, "",
                f"{group}'s root declares no exit_gain_loss_account, but {sorted(entities)} exit it with "
                "balances carried: assert_exit_accounts_declared fails the build")
            self.assertIn(account, chart, f"{account} is not in the fixture's chart")
            row = chart[account]
            self.assertEqual((row["status"], row["is_group"], row["statement_section"]),
                             ("Published", 0, "Profit and Loss"),
                             f"{account} is not a Published P&L posting leaf")

    def test_the_teardown_removes_the_account(self):
        roots = [r for r in _rows(self.text, "epm_gold.consolidation_groups")
                 if r["consolidation_group"] == "ZZGRP" and r["data_area_id"] == ""]
        account = roots[0].get("exit_gain_loss_account", "") if roots else ""
        with open(os.path.join(PROJECT_ROOT, "tests", "integration", "ic_decisions_expectations.py")) as f:
            expectations = f.read()
        m = re.search(r"^FIXTURE_ACCOUNTS = \(([^)]*)\)", expectations, re.M)
        self.assertTrue(m)
        self.assertNotEqual(account, "")
        self.assertIn(f'"{account}"', m.group(1), "the teardown would leave the account in epm_staging.main_accounts")


if __name__ == "__main__":
    unittest.main()
