"""fixture_gate creates, as zzg_*, the init-db.sql tables the stack lacks, and
adds the fixtures' budget dimension columns (one definition: init-db.sql)."""
import importlib.util
import os
import unittest

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def _gate():
    spec = importlib.util.spec_from_file_location(
        "fixture_gate", os.path.join(REPO, "scripts", "fixture_gate.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class MissingTables(unittest.TestCase):
    def test_init_db_tables_include_budget_entries(self):
        ddl = _gate().init_db_tables()
        self.assertIn("epm_raw.budget_entries", ddl)
        self.assertTrue(ddl["epm_raw.budget_entries"].lstrip().startswith("CREATE TABLE"))

    def test_only_missing_tables_are_created_as_zzg(self):
        g = _gate()
        wanted = {"epm_raw.budget_entries", "epm_gold.budget_annual_input"}
        have = {"epm_gold.budget_annual_input": "MergeTree"}
        stmts = g.missing_table_statements(wanted, have, g.PREFIX)
        self.assertEqual(len(stmts), 1)
        self.assertIn("zzg_raw.budget_entries", stmts[0])
        self.assertNotIn("epm_", stmts[0])

    def test_nothing_missing_nothing_created(self):
        g = _gate()
        have = {"epm_raw.budget_entries": "MergeTree"}
        self.assertEqual(g.missing_table_statements({"epm_raw.budget_entries"}, have, g.PREFIX), [])

    def test_dimension_columns_only_for_tables_in_scratch(self):
        g = _gate()
        stmts = g.scratch_dimension_columns({"zzg_raw.budget_entries"})
        self.assertTrue(stmts)
        self.assertTrue(all("zzg_raw.budget_entries" in s for s in stmts))
        self.assertTrue(any("dim_cost_center" in s for s in stmts))
        self.assertFalse(any("dim_business_unit" in s for s in stmts))  # not in_budget

    def test_no_fixture_creates_budget_entries_itself(self):
        d = os.path.join(REPO, "dbt_project", "test_fixtures")
        bad = [f for f in os.listdir(d) if f.endswith(".sql")
               and "CREATE TABLE IF NOT EXISTS epm_raw.budget_entries" in open(os.path.join(d, f)).read()]
        self.assertEqual(bad, [])


if __name__ == "__main__":
    unittest.main()
