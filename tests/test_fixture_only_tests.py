"""konsol#348 S4 (W3 review): a singular test that re-runs the consolidation
core is a fixture-only test. It runs in CI and in the fixture gate, never in a
site's build.

assert_consolidation_core_grain_extra_is_a_partition runs consolidation_core()
twice over the whole partner trial balance. On a site it cost about twice the
model it guards (2.49 s, ~11% of a full build), and when it errors dbt skips
gold_consolidated_trial_balance's children, so a site build produces no
consolidated trial balance. The test is therefore disabled by default
(`config(enabled=var('fixture_only_tests', false))`), and the two places that
run dbt on fixture data enable it through the one `--vars` payload they already
pass: `fixture_dimension_vars()` and `zero_dimension_vars()` in
scripts/tb_only_first_build.py, used by scripts/fixture_gate.py (the gate's
parse, prepare-ci run and every fixture, at the fixture dimensions and at zero
dimensions) and scripts/ci_full_build.py (the full build, at both). dbt takes
one --vars flag, so the var must ride in that payload, not in a second flag.

Plain unittest, no third-party imports:
`python -m unittest -v tests.test_fixture_only_tests`
"""
import importlib.util
import json
import os
import re
import unittest

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPTS = os.path.join(PROJECT_ROOT, "scripts")
TESTS_DIR = os.path.join(PROJECT_ROOT, "dbt_project", "tests")
WORKFLOW = os.path.join(PROJECT_ROOT, ".github", "workflows", "dbt-checks.yml")
PARTITION_TEST = os.path.join(TESTS_DIR, "assert_consolidation_core_grain_extra_is_a_partition.sql")

VAR = "fixture_only_tests"
#: the config line a fixture-only test carries, whitespace-tolerant
FIXTURE_ONLY_CONFIG = re.compile(
    r"\{\{\s*config\(\s*enabled\s*=\s*var\(\s*'%s'\s*,\s*false\s*\)\s*\)\s*\}\}" % VAR)


def _load(name):
    spec = importlib.util.spec_from_file_location(name, os.path.join(SCRIPTS, name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _vars_payload(argv):
    """The JSON dict after the one --vars flag in a dbt argv fragment."""
    assert argv.count("--vars") == 1, argv
    return json.loads(argv[argv.index("--vars") + 1])


def _read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


class PartitionTestIsFixtureOnly(unittest.TestCase):
    def test_disabled_by_default_and_the_config_precedes_the_query(self):
        sql = _read(PARTITION_TEST)
        m = FIXTURE_ONLY_CONFIG.search(sql)
        self.assertIsNotNone(m, "the partition test does not carry config(enabled=var('fixture_only_tests', false))")
        self.assertLess(m.start(), sql.index("\nwith "), "the config must come before the query")

    def test_every_test_that_calls_the_core_is_fixture_only(self):
        """The rule, not the one file: a second test that re-runs the core would cost the same."""
        offenders = []
        for root, _dirs, files in os.walk(TESTS_DIR):
            for name in files:
                if not name.endswith(".sql"):
                    continue
                sql = _read(os.path.join(root, name))
                if "consolidation_core(" in sql and not FIXTURE_ONLY_CONFIG.search(sql):
                    offenders.append(name)
        self.assertEqual(offenders, [])

    def test_the_first_non_comment_line_starts_the_query(self):
        """W3 review finding 1: `{%- set -%}` blocks after the header trimmed the
        newline that closed the last comment line, so the compiled SQL began
        `-- ... not expected).with base_source as (`: the first CTE inside the
        comment, and an unmatched parenthesis. The config line after the header
        is kept apart from the trimming blocks by a line that is not trimmed."""
        sql = _read(PARTITION_TEST)
        lines = sql.splitlines()
        first_code = next(i for i, l in enumerate(lines) if l.strip() and not l.lstrip().startswith("--"))
        self.assertTrue(lines[first_code].startswith("{{ config("), lines[first_code])
        # the line after the config is blank or a non-trimming line, so the comment's newline survives
        self.assertFalse(lines[first_code + 1].lstrip().startswith("{%-"), lines[first_code + 1])


class RunnersEnableFixtureOnlyTests(unittest.TestCase):
    def setUp(self):
        self.tb = _load("tb_only_first_build")

    def test_fixture_dimension_vars_enable_them(self):
        payload = _vars_payload(self.tb.fixture_dimension_vars())
        self.assertEqual(payload.get(VAR), True, payload)
        self.assertEqual(payload["dimensions"], self.tb.FIXTURE_DIMENSIONS)

    def test_zero_dimension_vars_enable_them_too(self):
        payload = _vars_payload(self.tb.zero_dimension_vars())
        self.assertEqual(payload.get(VAR), True, payload)
        self.assertEqual(payload["dimensions"], [])

    def test_the_gate_and_the_full_build_take_the_zero_dimension_payload_from_the_helper(self):
        gate = _load("fixture_gate")
        full = _load("ci_full_build")
        self.assertEqual(gate.ZERO_DIM_VARS, self.tb.zero_dimension_vars())
        self.assertEqual(full.ZERO_DIM_BUILD[-2:], self.tb.zero_dimension_vars())
        self.assertEqual(full.FULL_BUILD[-2:], self.tb.fixture_dimension_vars())
        for name in ("fixture_gate.py", "ci_full_build.py"):
            self.assertNotIn('"dimensions": []', _read(os.path.join(SCRIPTS, name)),
                             f"{name} builds its own zero-dimension --vars; use zero_dimension_vars()")

    def test_ci_runs_this_pin_and_watches_its_inputs(self):
        wf = _read(WORKFLOW)
        self.assertIn("python -m unittest -v tests.test_fixture_only_tests", wf)
        self.assertEqual(wf.count("- 'tests/test_fixture_only_tests.py'"), 2,
                         "push and pull_request paths must both list this test")


if __name__ == "__main__":
    unittest.main()
