"""konsol#269 (cost allocation phase 1, task W7): scripts/extract_assertion_rules.py
finds singular tests in subfolders of dbt_project/tests/, not only the top level.

Without this, the cost allocation assertions in dbt_project/tests/cost_allocation/
are missing from docs/design/rules.md. The test runs the script on a temporary
tree, so it does not depend on the real test files.

Plain unittest, no third-party imports:
`python3 -m unittest -v tests.test_extract_assertion_rules`.
"""
import importlib.util
import io
import os
import pathlib
import tempfile
import unittest
from contextlib import redirect_stdout

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPT = os.path.join(PROJECT_ROOT, "scripts", "extract_assertion_rules.py")


def load_script():
    spec = importlib.util.spec_from_file_location("extract_assertion_rules", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def run_on_tree(files):
    """Write `files` (relative path under dbt_project/tests -> SQL text), run the
    script against that tree, and return the generated rules.md text."""
    module = load_script()
    with tempfile.TemporaryDirectory() as root:
        root_path = pathlib.Path(root)
        tests = root_path / "dbt_project" / "tests"
        for rel, body in files.items():
            path = tests / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(body, encoding="utf-8")
        out = root_path / "docs" / "design" / "rules.md"
        module.ROOT, module.TESTS, module.OUT = root_path, tests, out
        with redirect_stdout(io.StringIO()):
            assert module.main() == 0
        return out.read_text(encoding="utf-8")


class SubfolderAssertionsAreExtracted(unittest.TestCase):
    def test_test_in_subfolder_is_listed_with_its_path(self):
        text = run_on_tree({
            "assert_top_level_rule.sql": "-- Test: the top level rule holds.\nselect 1 where false\n",
            "cost_allocation/assert_cost_allocation_sub_rule.sql":
                "-- Test: the subfolder rule holds.\nselect 1 where false\n",
        })
        self.assertIn("### `top_level_rule`", text)
        self.assertIn("### `cost_allocation_sub_rule`", text)
        self.assertIn("`tests/cost_allocation/assert_cost_allocation_sub_rule.sql`", text)

    def test_non_assertion_sql_in_subfolder_is_ignored(self):
        text = run_on_tree({
            "cost_allocation/helper.sql": "select 1\n",
            "cost_allocation/assert_real.sql": "-- Test: real rule.\nselect 1 where false\n",
        })
        self.assertIn("### `real`", text)
        self.assertNotIn("helper", text)


if __name__ == "__main__":
    unittest.main()
