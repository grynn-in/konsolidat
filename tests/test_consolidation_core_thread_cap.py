"""konsolidat#369: the consolidation core keeps ClickHouse's thread cap on an
empty warehouse, and the budget model adds no window stage the actuals lack.

Measured on CI's clickhouse-server 24.8.14.39 (4 cores), the first build of a
fresh TB-only site, every table empty (workflow run 44011900096 of the
bisect-369-lab scratch branch, 17 Nov 2026):

  statement                                  max_threads  peak threads  result
  gold_consolidated_budget_tb (ab86c12)            4          9,246     CANNOT_SCHEDULE_TASK (pool 10,000)
  gold_consolidated_budget_tb (ab86c12)            1            257     ok
  gold_consolidated_trial_balance                  4             51     ok
  gold_consolidated_trial_balance                  8            163     ok
  budget + materialize('') partner                 4             51     ok
  budget + system.one in the join tree             4              5     ok
  budget + both                                    4              5     ok
  budget (ab86c12) + one row in budget_cycles      4              5     ok

Two ClickHouse 24.8 behaviours combine, both read off EXPLAIN PIPELINE:

1. A plan whose EVERY table expression is an empty MergeTree table carries no
   max_threads cap: the planner sets the cap only on a table read that produced
   a step, and an empty table becomes "Read from NullSource" instead. Without
   the cap the sort before each window step scatters its input by partition
   into getNumThreads() streams, which is then the pipeline's accumulated
   stream count, not the setting; stacked window steps therefore multiply the
   streams (5 -> 10 -> 50 at max_threads 4), and the executor starts one thread
   per stream. One non-empty table anywhere in the join tree restores the cap
   (the budget_cycles probe). system.one is a storage that always produces a
   read step, so `cross join system.one` in the core's entity_tb keeps the cap
   whatever the tables hold: peak threads = max_threads + 1 in every run.
   The IN-subquery predicate is a separate plan: system.one inside it did
   nothing (lab round 2).

2. The budget wrote its partner as the constant '' (a budget has no partner),
   in every window partition. A constant in the sort key loses the sorted-
   stream property between `retranslated` and `close_pnl`, so the budget sorted
   and scattered a third time (5 -> 10 -> 50 -> 500 window transforms against
   the actuals' 5 -> 10 -> 50), and that third stage is what exhausted the
   10,000-thread pool on 4 cores. materialize('') is a column, not a constant:
   the budget's pipeline then has the actuals' shape (71 window transforms).

Neither is fixed by query_plan_enable_multithreading_after_window_functions
= 0, which both models keep (it removes the resize AFTER each window; the
scatter is in the sort BEFORE it), nor by a smaller statement (ab86c12 took the
SQL from 33 KB to 21 KB and changed nothing), nor by removing rate_set_column,
grain_extra or the with_set join (identical processor counts, lab round 1).

Plain unittest, no third-party imports:
`python -m unittest -v tests.test_consolidation_core_thread_cap`
"""
import os
import re
import unittest

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CORE = os.path.join(PROJECT_ROOT, "dbt_project", "macros", "consolidation_core.sql")
BUDGET = os.path.join(PROJECT_ROOT, "dbt_project", "models", "gold", "gold_consolidated_budget_tb.sql")
ACTUALS = os.path.join(PROJECT_ROOT, "dbt_project", "models", "gold", "gold_consolidated_trial_balance.sql")


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def strip_jinja_comments(text):
    return re.sub(r"\{#.*?#\}", "", text, flags=re.S)


class ThreadCapTests(unittest.TestCase):
    def test_core_entity_tb_anchors_the_plan_on_system_one(self):
        """The source CTE is cross-joined with system.one before the other joins,
        so the plan always holds one table read that produced a step and
        ClickHouse keeps max_threads as the cap (konsolidat#369, behaviour 1)."""
        core = strip_jinja_comments(read(CORE))
        m = re.search(r"from \{\{ source_cte \}\} as tb\s+cross join system\.one\b", core)
        self.assertIsNotNone(
            m, "consolidation_core.sql: entity_tb must read `from {{ source_cte }} as tb cross join system.one` "
               "(konsolidat#369: an all-empty plan has no max_threads cap without it)")
        self.assertEqual(core.count("cross join system.one"), 1,
                         "one anchor, in entity_tb; the IN-subquery predicates are separate plans and gain nothing")
        self.assertIn("konsolidat#369", read(CORE), "the anchor cites the issue that measured it")

    def test_budget_partner_is_a_column_not_a_constant(self):
        """The budget's partner is materialize(''), never a bare '' constant:
        a constant in every window partition cost a third sort-and-scatter
        stage (konsolidat#369, behaviour 2)."""
        budget = strip_jinja_comments(read(BUDGET))
        self.assertIsNone(
            re.search(r"(?<![\w(])''\s+as\s+partner_data_area_id", budget),
            "gold_consolidated_budget_tb.sql writes `'' as partner_data_area_id`: a constant partition column; "
            "use materialize('') (konsolidat#369)")
        self.assertRegex(budget, r"materialize\(''\)\s+as\s+partner_data_area_id")

    def test_both_consolidation_models_keep_the_window_setting(self):
        """query_plan_enable_multithreading_after_window_functions stays 0 on
        both callers of the core (the earlier TB-only fix); it is necessary,
        not sufficient."""
        for path in (ACTUALS, BUDGET):
            self.assertRegex(read(path), r"'query_plan_enable_multithreading_after_window_functions'\s*:\s*0",
                             os.path.basename(path))


if __name__ == "__main__":
    unittest.main()
