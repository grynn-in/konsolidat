"""fixture_gate: a seed statement that ClickHouse refuses fails THAT fixture with a
reason, instead of crashing the gate (konsol#348 S4b live test, finding 2).

On 8069 a must_flag fixture seeding gold_fully_consolidated_budget, a model
not yet built on the stack, raised `Code: 60 ... Could not find table` out of
run_fixture's `client.command(stmt)`; the fixture got no verdict and the rest
of the chunk was lost. The gate now classifies the error per fixture:
seed_problem(stmt, error) names the table and says what to do, and
run_fixture returns ("failed", [that]) and moves on.

Plain unittest, no ClickHouse: the classifier is pure.
`python -m unittest -v tests.test_fixture_gate_seed_errors`
"""
import importlib.util
import os
import unittest

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

MISSING = ("HTTPDriver for http://localhost:8123 returned response code 404)\n"
           " Code: 60. DB::Exception: Could not find table: gold_fully_consolidated_budget. "
           "(UNKNOWN_TABLE) (version 24.8.4.13 (official build))")


def _gate():
    spec = importlib.util.spec_from_file_location(
        "fixture_gate", os.path.join(REPO, "scripts", "fixture_gate.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class SeedErrors(unittest.TestCase):
    def test_a_missing_table_names_the_table_and_the_remedy(self):
        g = _gate()
        stmt = ("INSERT INTO zzg_gold.gold_fully_consolidated_budget\n  (consolidation_group, amount)\n"
                "VALUES\n  ('ZZG', 1)")
        problem = g.seed_problem(stmt, MISSING)
        self.assertIn("zzg_gold.gold_fully_consolidated_budget", problem)
        self.assertIn("epm_gold.gold_fully_consolidated_budget", problem)
        self.assertIn("does not exist on this stack", problem)
        self.assertIn("build the model first", problem)
        self.assertIn("UNKNOWN_TABLE", problem)

    def test_a_missing_table_in_an_alter_is_named_too(self):
        g = _gate()
        stmt = "ALTER TABLE zzg_gold.gold_consolidated_budget_tb ADD COLUMN IF NOT EXISTS dim_cost_center String"
        problem = g.seed_problem(stmt, MISSING)
        self.assertIn("zzg_gold.gold_consolidated_budget_tb", problem)
        self.assertIn("does not exist on this stack", problem)

    def test_any_other_error_quotes_the_statement_and_the_first_error_line(self):
        g = _gate()
        stmt = "INSERT INTO zzg_raw.budget_entries (x) VALUES (1)"
        problem = g.seed_problem(stmt, "Code: 16. DB::Exception: No such column x in table\nsecond line")
        self.assertIn("INSERT INTO zzg_raw.budget_entries", problem)
        self.assertIn("No such column x", problem)
        self.assertNotIn("second line", problem)
        self.assertNotIn("does not exist on this stack", problem)

    def test_run_fixture_catches_seed_errors(self):
        """The seed loop is wrapped: the except names seed_problem, and the fixture is
        failed, not the gate (a static check; the loop itself needs ClickHouse)."""
        with open(os.path.join(REPO, "scripts", "fixture_gate.py"), encoding="utf-8") as f:
            src = f.read()
        self.assertIn("seed_problem(stmt", src)
        start = src.index("def run_fixture(")
        body = src[start:src.index("\ndef ", start + 1)]
        self.assertIn("except Exception", body)
        self.assertIn('return "failed", [problem]', body)


if __name__ == "__main__":
    unittest.main()
