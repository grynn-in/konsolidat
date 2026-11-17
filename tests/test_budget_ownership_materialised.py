"""konsolidat#369: the budget's ownership resolution is materialised ONCE.

gold_consolidated_budget_tb inlined ownership_resolution_ctes() (a ~300-line
chain with 13 internal CTE references) as the core's ownership_cte, and the
core reads its `rated` CTE four times, each copy inlining the chain again;
budget_rate_guard's gap query planned it a fifth time. ClickHouse inlines
every CTE reference, so the compiled SELECT was 33 KB against the CTB's 18 KB,
the live CREATE and INSERT took ~6.6 s each on an EMPTY budget (analysis, not
data), and CI's ClickHouse ran out of threads (CANNOT_SCHEDULE_TASK, code 439).

The fix: gold_budget_entity_ownership (table) holds the budget's ownership
resolution on the budget's own period spine, and every budget reader of
ownership reads that table:

  - gold_consolidated_budget_tb passes ownership_cte=ref('gold_budget_entity_ownership');
  - budget_rate_gaps() (macros/budget_rates.sql: the pre_hook guard and the
    singular rate test) joins it;
  - assert_budget_declared_historical_has_a_rate joins it for owner_group.

None of those three may call ownership_resolution_ctes() again; only the new
model does, among the budget files. Plain unittest, static source.
`python -m unittest -v tests.test_budget_ownership_materialised`
"""
import os
import re
import unittest

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DBT = os.path.join(PROJECT_ROOT, "dbt_project")

OWNERSHIP_MODEL = os.path.join(DBT, "models", "gold", "gold_budget_entity_ownership.sql")
READERS = {
    "gold_consolidated_budget_tb": os.path.join(DBT, "models", "gold", "gold_consolidated_budget_tb.sql"),
    "budget_rates macro": os.path.join(DBT, "macros", "budget_rates.sql"),
    "assert_budget_declared_historical_has_a_rate":
        os.path.join(DBT, "tests", "assert_budget_declared_historical_has_a_rate.sql"),
}
# A Jinja CALL of the macro; its name in a comment is documentation, not a resolution.
RESOLVES = re.compile(r"\{\{-?\s*ownership_resolution_ctes\s*\(")
REF = re.compile(r"ref\(\s*['\"]gold_budget_entity_ownership['\"]\s*\)")


def _read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


class BudgetOwnershipMaterialised(unittest.TestCase):
    def test_the_ownership_model_exists_and_resolves_the_graph_once(self):
        self.assertTrue(os.path.exists(OWNERSHIP_MODEL), f"missing {OWNERSHIP_MODEL}")
        src = _read(OWNERSHIP_MODEL)
        self.assertEqual(len(RESOLVES.findall(src)), 1)
        self.assertIn("budget_consolidation_inputs(", src)

    def test_no_budget_reader_resolves_ownership_itself(self):
        hits = {name: len(RESOLVES.findall(_read(p))) for name, p in READERS.items()}
        self.assertEqual({k: v for k, v in hits.items() if v}, {},
                         f"budget readers still inline ownership_resolution_ctes(): {hits}")

    def test_every_budget_reader_reads_the_materialised_table(self):
        missing = [name for name, p in READERS.items() if not REF.search(_read(p))]
        self.assertEqual(missing, [], f"budget readers not reading gold_budget_entity_ownership: {missing}")

    def test_the_core_takes_the_table_as_its_ownership(self):
        src = _read(READERS["gold_consolidated_budget_tb"])
        self.assertRegex(src, r"ownership_cte\s*=\s*ref\(\s*['\"]gold_budget_entity_ownership['\"]\s*\)")


if __name__ == "__main__":
    unittest.main()
