"""konsolidat#335 (#358 review F1, F2): the consolidation core applies the
re-entry stint reset only when its caller passes the exit events.

The reset (spine_stints, macros/consolidation_core.sql) is correct for the
actuals only because gold_ownership_exit_journal derecognises the pre-exit
balance and the acquisition journal's line (0) brings it back. A budget posts
neither journal, so the reset would be wrong there (F2), and reading
gold_ownership_exits from a `tag:domain:scenarios` build reads a table that
build never makes: unknown on a fresh site, stale otherwise (F1).

So consolidation_core takes `exits_relation=none`, a trailing keyword:
  - none: no reset, stint = 0 on every row, and no join or ref to the exits;
  - gold_consolidated_trial_balance passes ref('gold_ownership_exits').
The DAG check runs `dbt ls` (no connection needed) when dbt is on the host:
the budget model's parents exclude gold_ownership_exits, the CTB's include it.

Plain unittest: `python -m unittest -v tests.test_consolidation_core_exits_relation`
"""
import os
import re
import shutil
import subprocess
import unittest

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DBT_PROJECT = os.path.join(PROJECT_ROOT, "dbt_project")
CORE = os.path.join(DBT_PROJECT, "macros", "consolidation_core.sql")
ACTUALS = os.path.join(DBT_PROJECT, "models", "gold", "gold_consolidated_trial_balance.sql")
BUDGET = os.path.join(DBT_PROJECT, "models", "gold", "gold_consolidated_budget_tb.sql")


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def strip_jinja_comments(text):
    return re.sub(r"\{#.*?#\}", "", text, flags=re.S)


def find_dbt():
    """KONSOLIDAT_DBT, then the repo's own .venv, then PATH; None skips."""
    candidates = [os.environ.get("KONSOLIDAT_DBT"),
                  os.path.join(PROJECT_ROOT, ".venv", "bin", "dbt"),
                  shutil.which("dbt")]
    for c in candidates:
        if c and os.path.exists(c):
            return c
    return None


def dbt_parents(dbt, model):
    out = subprocess.run(
        [dbt, "ls", "--project-dir", DBT_PROJECT, "--profiles-dir", DBT_PROJECT,
         "--select", "+" + model, "--resource-type", "model", "--output", "name", "-q"],
        capture_output=True, text=True, timeout=600)
    if out.returncode != 0:
        raise AssertionError("dbt ls failed:\n" + out.stdout + out.stderr)
    return {line.strip() for line in out.stdout.splitlines() if line.strip()}


class ExitsRelationTests(unittest.TestCase):
    def test_core_takes_exits_relation_trailing_default_none(self):
        core = read(CORE)
        m = re.search(r"\{%\s*macro\s+consolidation_core\((.*?)\)\s*%\}", core, flags=re.S)
        self.assertIsNotNone(m, "consolidation_core macro signature not found")
        params = [p.strip() for p in m.group(1).split(",")]
        self.assertEqual(params[-1], "exits_relation=none",
                         "exits_relation=none must be the trailing keyword parameter")
        self.assertTrue(re.search(r"\n\s+exits_relation\s{2,}", core), "document exits_relation in the macro header")

    def test_core_refs_no_exit_model_itself(self):
        """The core reads the exits only through exits_relation: a ref inside
        the macro would make every caller, the budget too, depend on it."""
        body = strip_jinja_comments(read(CORE))
        self.assertFalse("gold_ownership_exits" in body,
                         "consolidation_core.sql names gold_ownership_exits outside a comment")
        self.assertTrue(re.search(r"\{\{\s*exits_relation\s*\}\}", body),
                        "consolidation_core.sql must read the exits as {{ exits_relation }}")

    def test_actuals_pass_the_exits(self):
        self.assertTrue(re.search(r"exits_relation\s*=\s*ref\(\s*'gold_ownership_exits'\s*\)",
                                  strip_jinja_comments(read(ACTUALS))),
                        "gold_consolidated_trial_balance must pass exits_relation=ref('gold_ownership_exits')")

    def test_budget_uses_the_default(self):
        self.assertFalse("exits_relation" in strip_jinja_comments(read(BUDGET)),
                         "the budget takes the default (no reset): it posts no exit journal")

    def test_dag_budget_has_no_exits_parent_actuals_do(self):
        dbt = find_dbt()
        if dbt is None:
            self.skipTest("dbt not installed (set KONSOLIDAT_DBT)")
        self.assertNotIn("gold_ownership_exits", dbt_parents(dbt, "gold_consolidated_budget_tb"))
        self.assertIn("gold_ownership_exits", dbt_parents(dbt, "gold_consolidated_trial_balance"))


if __name__ == "__main__":
    unittest.main()
