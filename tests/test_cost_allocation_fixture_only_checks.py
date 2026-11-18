"""Checks keyed to fixture data run only under the fixture gate (konsol#269, RF8)."""
import os
import unittest

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TESTS = os.path.join(REPO, "dbt_project", "tests", "cost_allocation")
VAR = "fixture_only_tests"


def read(*p):
    with open(os.path.join(REPO, *p), encoding="utf-8") as f:
        return f.read()


class FixtureOnlyChecks(unittest.TestCase):
    def test_expected_values_enabled_only_by_the_fixture_var(self):
        text = read("dbt_project", "tests", "cost_allocation", "assert_cost_allocation_expected_values.sql")
        self.assertIn(f"enabled=var('{VAR}', false)", text)

    def test_both_checks_are_fixture_only_and_named_by_a_fixture(self):
        # main's mechanism (konsol#348 S4): enabled only for a fixture that names the test
        fx = os.path.join(REPO, "dbt_project", "test_fixtures")
        for t in ("assert_cost_allocation_expected_values", "assert_cost_allocation_frozen_no_idle_backfill"):
            self.assertIn(f"enabled=var('{VAR}', false)", read("dbt_project", "tests", "cost_allocation", t + ".sql"))
            self.assertTrue(any(f.startswith(t + ".") for f in os.listdir(fx)), t)

    def test_backfill_is_a_macro_gated_on_a_count(self):
        text = read("dbt_project", "models", "gold", "gold_cost_allocation_frozen.sql")
        self.assertNotIn("UPDATE hop_kind", text.split("{{ cost_allocation_lines", 1)[0].split("pre_hook")[1])
        macro = read("dbt_project", "macros", "cost_allocation.sql")
        self.assertIn("run_query", macro)


if __name__ == "__main__":
    unittest.main()
