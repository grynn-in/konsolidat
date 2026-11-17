"""konsol#348 S4 (W3 review): a singular test that re-runs the consolidation
core is a fixture-only test. It runs in CI and in the fixture gate, never in a
site's build.

assert_consolidation_core_grain_extra_is_a_partition runs consolidation_core()
twice over the whole partner trial balance. On a site it cost about twice the
model it guards (2.49 s, ~11% of a full build), and when it errors dbt skips
gold_consolidated_trial_balance's children, so a site build produces no
consolidated trial balance. The test is therefore disabled by default
(`config(enabled=var('fixture_only_tests', false))`), and the runs on fixture
data enable it through the one `--vars` payload they already pass:
`fixture_dimension_vars(fixture_only=True)` / `zero_dimension_vars(fixture_only=True)`
in scripts/tb_only_first_build.py. dbt takes one --vars flag, so the var must
ride in that payload, not in a second flag.

Who enables it (W3 review, round 2): ONLY a fixture that names a fixture-only
test, in its `-- gate: expect` line or by its file name. Passing the var on
every gate call enabled the test inside `closing_period_rates.must_flag.sql`'s
build of `+gold_consolidated_trial_balance`: the test calls the core on data
where the core is meant to throw (a missing rate), errored first, and dbt
SKIPPED the model the fixture expected REFUSED (74/75). The gate's `parse`
alone always carries the var, so the manifest knows the test's parents when a
fixture needs them. scripts/ci_full_build.py keeps the var on both legs: a
full build has no refuse path (every ERROR or SKIP fails it). The TB-only
first build passes no --vars at all (its dimensions come from the project
copy), so the test is disabled there. judge() never accepts SKIPPED for a
`refuse` expectation.

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

    def test_fixture_dimension_vars_enable_them_only_when_asked(self):
        plain = _vars_payload(self.tb.fixture_dimension_vars())
        self.assertNotIn(VAR, plain, plain)
        self.assertEqual(plain["dimensions"], self.tb.FIXTURE_DIMENSIONS)
        on = _vars_payload(self.tb.fixture_dimension_vars(fixture_only=True))
        self.assertEqual(on.get(VAR), True, on)
        self.assertEqual(on["dimensions"], self.tb.FIXTURE_DIMENSIONS)

    def test_zero_dimension_vars_enable_them_only_when_asked(self):
        plain = _vars_payload(self.tb.zero_dimension_vars())
        self.assertNotIn(VAR, plain, plain)
        self.assertEqual(plain["dimensions"], [])
        on = _vars_payload(self.tb.zero_dimension_vars(fixture_only=True))
        self.assertEqual(on.get(VAR), True, on)
        self.assertEqual(on["dimensions"], [])

    def test_fixture_only_tests_are_found_by_their_config(self):
        self.assertEqual(self.tb.fixture_only_tests(),
                         {"assert_consolidation_core_grain_extra_is_a_partition",
                          "assert_cost_allocation_expected_values",
                          "assert_cost_allocation_frozen_no_idle_backfill"})

    def test_the_full_build_enables_them_on_both_legs_from_the_helper(self):
        """No refuse path runs in ci_full_build.py: every ERROR or SKIP fails it."""
        full = _load("ci_full_build")
        self.assertEqual(full.FULL_BUILD[-2:], self.tb.fixture_dimension_vars(fixture_only=True))
        self.assertEqual(full.ZERO_DIM_BUILD[-2:], self.tb.zero_dimension_vars(fixture_only=True))
        for name in ("fixture_gate.py", "ci_full_build.py"):
            self.assertNotIn('"dimensions": []', _read(os.path.join(SCRIPTS, name)),
                             f"{name} builds its own zero-dimension --vars; use zero_dimension_vars()")


class GateEnablesThemPerFixture(unittest.TestCase):
    """W3 review, round 2: the var goes only to a fixture that names a fixture-only test."""

    def setUp(self):
        self.g = _load("fixture_gate")

    def _payloads(self, fixture_path):
        plan = self.g.passes([self.g.spec(fixture_path)])
        self.assertTrue(plan)
        return [_vars_payload(v) for _s, v, _label in plan]

    def test_a_fixture_that_does_not_name_the_test_gets_no_var(self):
        """closing_period_rates.must_flag.sql builds +gold_consolidated_trial_balance and
        expects it REFUSED; with the var the partition test joined the build, errored on
        the missing rate first, and the model was SKIPPED instead."""
        for payload in self._payloads(os.path.join(self.g.FIXTURES, "closing_period_rates.must_flag.sql")):
            self.assertNotIn(VAR, payload, payload)
        # and a zero-dimension pass is as selective
        for payload in self._payloads(os.path.join(self.g.FIXTURES, "variance_budget_scenario.sql")):
            self.assertNotIn(VAR, payload, payload)

    def test_the_tests_own_fixture_gets_the_var(self):
        path = os.path.join(self.g.FIXTURES, "assert_consolidation_core_grain_extra_is_a_partition.sql")
        for payload in self._payloads(path):
            self.assertEqual(payload.get(VAR), True, payload)

    def test_a_build_fixture_that_expects_the_test_gets_the_var(self):
        import tempfile
        body = ("-- gate: build +gold_consolidated_trial_balance assert_consolidation_core_grain_extra_is_a_partition\n"
                "-- gate: expect assert_consolidation_core_grain_extra_is_a_partition pass\n"
                "INSERT INTO epm_gold.consolidation_groups (consolidation_group) VALUES ('ZZG');\n")
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "zz_probe.sql")
            with open(path, "w", encoding="utf-8") as f:
                f.write(body)
            for payload in self._payloads(path):
                self.assertEqual(payload.get(VAR), True, payload)

    def test_the_gate_parses_with_the_var_so_the_manifest_knows_the_tests_parents(self):
        self.assertEqual(_vars_payload(self.g.PARSE_VARS).get(VAR), True)

    def test_refuse_never_accepts_skipped(self):
        s = {"expect": [], "refuse": ("gold_consolidated_trial_balance", "konsolidat#93")}
        results = {"gold_consolidated_trial_balance": ("model", "skipped", None, "")}
        problems = self.g.judge(s, results, "")
        self.assertTrue(any("REFUSED" in p and "SKIPPED" in p for p in problems), problems)

    def test_ci_runs_this_pin_and_watches_its_inputs(self):
        wf = _read(WORKFLOW)
        self.assertIn("python -m unittest -v tests.test_fixture_only_tests", wf)
        self.assertEqual(wf.count("- 'tests/test_fixture_only_tests.py'"), 2,
                         "push and pull_request paths must both list this test")


if __name__ == "__main__":
    unittest.main()
