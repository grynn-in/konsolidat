"""Checks keyed to fixture data run only under the fixture gate (konsol#269, RF8)."""
import os
import unittest

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TESTS = os.path.join(REPO, "dbt_project", "tests", "cost_allocation")
VAR = "cost_allocation_fixture_values"


def read(*p):
    with open(os.path.join(REPO, *p), encoding="utf-8") as f:
        return f.read()


class FixtureOnlyChecks(unittest.TestCase):
    def test_expected_values_enabled_only_by_the_gate_var(self):
        text = read("dbt_project", "tests", "cost_allocation", "assert_cost_allocation_expected_values.sql")
        self.assertIn(f"enabled=var('{VAR}', false)", text)

    def test_gate_passes_the_var_in_every_pass(self):
        import importlib.util
        spec = importlib.util.spec_from_file_location("fixture_gate", os.path.join(REPO, "scripts", "fixture_gate.py"))
        g = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(g)
        import json
        for v in (g.DIM_VARS, g.ZERO_DIM_VARS):
            self.assertIs(json.loads(v[1]).get(VAR), True)

    def test_backfill_is_a_macro_gated_on_a_count(self):
        text = read("dbt_project", "models", "gold", "gold_cost_allocation_frozen.sql")
        self.assertNotIn("UPDATE hop_kind", text.split("{{ cost_allocation_lines", 1)[0].split("pre_hook")[1])
        macro = read("dbt_project", "macros", "cost_allocation.sql")
        self.assertIn("run_query", macro)


if __name__ == "__main__":
    unittest.main()
