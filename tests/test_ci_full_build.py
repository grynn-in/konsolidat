"""konsolidat#181: the whole warehouse must be built and asserted in CI.

CI ran `dbt parse`, a gold-domain coverage check, seven DDL contract tests and
one *scoped* build (`@silver_main_accounts`, scripts/tb_only_first_build.py).
`dbt parse` does not validate SQL, and the scoped build is not everything.
Measured on the graph at the time this landed: **375 nodes, 310 reachable from
`@silver_main_accounts`, 65 not** — 24 ERP sources and 41 nodes, including
eight singular assertions that ran nowhere in CI:

    assert_conversion_factor_known      assert_incremental_slice_preserved
    assert_exchange_rate_positive       assert_scope_resolves_to_entities
    assert_fx_magnitude_cases           assert_scoped_cash_flow_ytd_confined
    assert_hierarchy_no_circular_ref    assert_staging_not_stale

Three of those are the FX rate guards, and `tests/integration` never ran in CI
at all — it skips itself when ClickHouse is unreachable, which on a runner
with no service container is always.

So a new job builds the FULL project against a throwaway ClickHouse and then
runs the integration tests, failing on an error *or a skip*. It also builds a
second time with `dimensions: []`, which is the standing guard for
konsolidat#220 — a site that declares no dimensions could not build at all,
53 call sites across five macros, and nothing stopped that class returning.

Plain unittest, static-source, no third-party imports: this asserts what the
script and the workflow say, it does not run dbt (that is the job's own work).
`python -m unittest -v tests.test_ci_full_build` (.github/workflows/dbt-checks.yml).
"""
import os
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPT = os.path.join(ROOT, "scripts", "ci_full_build.py")
WORKFLOW = os.path.join(ROOT, ".github", "workflows", "dbt-checks.yml")

#: Assertions that no CI job reached before this one. If a later change makes
#: the full build stop covering one, this list is what says so.
PREVIOUSLY_UNCOVERED = (
    "assert_conversion_factor_known",
    "assert_exchange_rate_positive",
    "assert_fx_magnitude_cases",
    "assert_hierarchy_no_circular_ref",
    "assert_incremental_slice_preserved",
    "assert_scope_resolves_to_entities",
    "assert_scoped_cash_flow_ytd_confined",
    "assert_staging_not_stale",
)


def _read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


class ScriptExists(unittest.TestCase):
    def test_script_is_present_and_executable_as_a_module(self):
        self.assertTrue(os.path.exists(SCRIPT), "scripts/ci_full_build.py is missing")
        src = _read(SCRIPT)
        self.assertIn("def main(", src)
        self.assertIn('if __name__ == "__main__"', src)


class BuildsEverything(unittest.TestCase):
    """The point of the job: no --select, so nothing is quietly left out."""

    def test_the_build_is_not_scoped(self):
        src = _read(SCRIPT)
        self.assertIn("FULL_BUILD", src)
        # The scoped build has its own job; this one must not narrow the graph.
        self.assertNotIn("@silver_main_accounts", src)

    def test_an_error_fails_the_job(self):
        src = _read(SCRIPT)
        self.assertIn("ERROR", src)
        self.assertIn("SKIP", src,
                      "a skipped node is coverage that silently did not run")

    def test_a_missing_summary_line_fails_the_job(self):
        """dbt can exit non-zero before it prints `Done.`; treating a missing
        summary as success is how a build that never ran reads as green."""
        self.assertIn("no dbt summary line", _read(SCRIPT))


class ZeroDimensionGuard(unittest.TestCase):
    """konsolidat#220's standing guard — the defect class that a macro growing
    a new dim_select call site reintroduces."""

    def test_the_project_is_built_again_with_no_dimensions(self):
        src = _read(SCRIPT)
        self.assertIn("dimensions", src)
        self.assertIn("[]", src)

    def test_the_zero_dimension_leg_cites_its_issue(self):
        self.assertIn("220", _read(SCRIPT))


class IntegrationTests(unittest.TestCase):
    """They existed and never ran: no service container, so `ch` skipped them."""

    def test_the_integration_suite_is_run(self):
        self.assertIn("tests/integration", _read(SCRIPT))

    def test_a_skip_fails_the_job(self):
        """The issue is explicit: fail on any error OR skip. A suite that skips
        itself reports success having checked nothing."""
        src = _read(SCRIPT)
        self.assertTrue(
            "-p no:randomly" in src or "skipped" in src or "--strict" in src,
            "nothing detects a skipped integration test")
        self.assertIn("skip", src.lower())


class Workflow(unittest.TestCase):
    def setUp(self):
        self.wf = _read(WORKFLOW)

    def test_a_job_runs_the_script(self):
        self.assertIn("scripts/ci_full_build.py", self.wf)

    def test_the_job_has_a_clickhouse_service(self):
        # Pinned to the running stack's major version, as the scoped-build job is.
        self.assertIn("clickhouse/clickhouse-server:24.8", self.wf)
        self.assertGreaterEqual(
            self.wf.count("clickhouse/clickhouse-server:24.8"), 2,
            "the new job needs its own throwaway ClickHouse service")

    def test_the_job_installs_what_the_integration_tests_need(self):
        """pytest and requests are imported by tests/integration/conftest.py;
        without them the suite cannot even be collected."""
        self.assertIn("pytest", self.wf)
        self.assertIn("requests", self.wf)

    def test_the_new_paths_trigger_the_workflow(self):
        for path in ("scripts/ci_full_build.py", "tests/integration/**"):
            self.assertIn(path, self.wf, f"{path} does not trigger dbt-checks")

    def test_previously_uncovered_assertions_are_named_somewhere(self):
        """So the next person can tell what this job was built to cover."""
        blob = self.wf + _read(SCRIPT) + _read(os.path.abspath(__file__))
        for name in PREVIOUSLY_UNCOVERED:
            self.assertIn(name, blob)


if __name__ == "__main__":
    unittest.main()
