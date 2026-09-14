"""konsol#191/#192: assert_cast_to_decimal128_is_exact (the regression test for
cast_to_decimal128, dbt_project/tests/assert_cast_to_decimal128_is_exact.sql)
must actually run in CI as a named, must-pass check.

It already gets pulled into `dbt build --select @silver_main_accounts` today:
its `-- depends_on: {{ ref('bronze_trial_balance_submissions') }}` line makes
bronze_trial_balance_submissions.sql a real parent, and bronze_trial_balance_
submissions is itself an ancestor of silver_gl_entries (a descendant of
silver_main_accounts via its `ref('silver_main_accounts')`), so `@` pulls it
in and dbt's default (eager, and here even cautious) indirect selection adds
the test. The empty-site build's `Done.` TOTAL went from 269 (main before
konsol#192) to 270 (after) — one more node, matching the new test.

The problem is visibility, not selection: tb_only_first_build.py's `show()`
only ever prints ERROR/FAIL/WARN lines, the two MUST_CREATE 'OK created'
lines, and the final 'Done. PASS=' summary line. A *passing* singular test
produces none of those — it is folded, anonymously, into the PASS= count. A
human reading the CI log has no way to tell this test ran at all, and nothing
here is robust to `@silver_main_accounts`'s selection changing shape later.
scripts/tb_only_first_build.py must run it explicitly and by name, the same
way it already runs ERP_QUOTE_TESTS, as a must-pass check (ERP_QUOTE_TESTS are
the opposite: negative checks required to FAIL/WARN).

Plain unittest, no third-party imports, static-source: this checks the
script's source, it does not execute dbt (no ClickHouse in this job).
`python -m unittest -v tests.test_tb_only_first_build` (.github/workflows/dbt-checks.yml).
"""
import os
import re
import unittest

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPT = os.path.join(PROJECT_ROOT, "scripts", "tb_only_first_build.py")
CAST_TEST = "assert_cast_to_decimal128_is_exact"


def _read():
    with open(SCRIPT, encoding="utf-8") as f:
        return f.read()


class TbOnlyFirstBuildRunsTheCastTest(unittest.TestCase):

    def setUp(self):
        self.src = _read()

    def test_cast_test_is_named_in_the_script(self):
        self.assertIn(
            CAST_TEST, self.src,
            f"{os.path.basename(SCRIPT)} never mentions {CAST_TEST}: nothing "
            "makes CI run it by name, so a regression in it is invisible in "
            "the job log.",
        )

    def test_cast_test_runs_as_an_explicit_dbt_select(self):
        # Named (literally, or via the CAST_TEST constant) in a real
        # `dbt test --select ...` / `dbt build --select ...` invocation (a
        # run_dbt(...) args list), not merely in a comment.
        calls = re.findall(r'\[\s*"(?:test|build)"\s*,\s*"--select"[^\]]*\]', self.src)
        self.assertTrue(
            any(CAST_TEST in call or "CAST_TEST" in call for call in calls),
            f"no explicit `dbt test/build --select ...` call in "
            f"{os.path.basename(SCRIPT)} names {CAST_TEST}",
        )

    def test_cast_test_is_not_grouped_with_the_must_fail_erp_quote_tests(self):
        # ERP_QUOTE_TESTS are negative checks (must FAIL/WARN); the cast test
        # is a regression guard and must be required to PASS instead.
        erp_tuple = re.search(r"ERP_QUOTE_TESTS\s*=\s*\([^)]*\)", self.src, flags=re.S)
        self.assertIsNotNone(erp_tuple, "ERP_QUOTE_TESTS definition not found")
        self.assertNotIn(CAST_TEST, erp_tuple.group(0))

    def test_a_failing_cast_test_would_be_recorded_as_a_problem(self):
        # Immediately after the CAST_TEST dbt call, the script must check the
        # outcome and record a problem when it is not a clean pass — otherwise
        # running it is theatre: a regression would not fail the job.
        match = re.search(
            r'\[\s*"(?:test|build)"\s*,\s*"--select"[^\]]*\bCAST_TEST\b[^\]]*\]',
            self.src,
        )
        self.assertIsNotNone(
            match,
            f"no `dbt test/build --select ...` call in {os.path.basename(SCRIPT)} "
            "passes the CAST_TEST constant",
        )
        window = self.src[match.end(): match.end() + 600]
        self.assertIn(
            "problems", window,
            f"the {CAST_TEST} dbt call's result is never checked against "
            "`problems` within 600 chars: a failure would not fail the job",
        )


if __name__ == "__main__":
    unittest.main()
