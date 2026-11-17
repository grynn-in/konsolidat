"""konsol#348 S6: the interim one-approved-round rule is gone (comment
6892322044, 15 Nov 2026: "both are removed in S6").

Until S6 a forecast (scenario, fiscal year) could hold only one approved
round, because four readers summed rounds; konsol refused the second Approve
and assert_forecast_one_approved_round_until_s6 was the warehouse backstop.
S6-Q1 (b), decided by Deepak Pai on 17 Nov 2026, gives every reader the
declared current round (gold_forecast_current_round), so rounds sit side by
side and the interim test, its fixtures and every reference to them leave
together with konsol's refusal (the two PRs merge together).

This pins that nothing in the dbt project or the CI workflow still names the
interim rule. Plain unittest, no third-party imports:
`python -m unittest -v tests.test_no_interim_forecast_rule`
"""
import os
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCANNED = ("dbt_project", ".github")
NEEDLES = ("until_s6", "one_approved_round")
SKIP_DIRS = {"target", "dbt_packages", "logs", "__pycache__"}


def _references():
    found = []
    for top in SCANNED:
        for root, dirs, files in os.walk(os.path.join(ROOT, top)):
            dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
            for name in files:
                path = os.path.join(root, name)
                rel = os.path.relpath(path, ROOT)
                if any(n in name for n in NEEDLES):
                    found.append(rel)
                    continue
                if not name.endswith((".sql", ".yml", ".yaml", ".py", ".md")):
                    continue
                with open(path, encoding="utf-8", errors="replace") as f:
                    text = f.read()
                if any(n in text for n in NEEDLES):
                    found.append(rel)
    return sorted(set(found))


class InterimForecastRuleIsGone(unittest.TestCase):
    def test_nothing_names_the_interim_rule(self):
        self.assertEqual(_references(), [])


if __name__ == "__main__":
    unittest.main()
