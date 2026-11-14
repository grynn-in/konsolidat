"""konsol#348 (konsolidat#189 PR3, A13): no period is dated by its number.

`build_date_from_year_period(year, period)` made the first day of the calendar
month a period number names: FY2026 P1 became 2026-01-01 whatever the site's
fiscal year. An April-March site's P1 is April 2025, so every reader that fell
back on it dated a period nine months late. The declared calendar is the one
source of period dates (macros/declared_periods.sql, konsol's fiscal calendar
in epm_staging.fiscal_periods); a period it does not declare is named by the
tests, never dated by a guess.

This guard fails when the macro, or a call to it, comes back anywhere in
dbt_project (models, macros, tests, test fixtures, analyses).

Plain unittest, static source, no third-party imports.
`python -m unittest -v tests.test_no_month_period_macro`
"""
import os
import unittest

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DBT = os.path.join(PROJECT_ROOT, "dbt_project")
NAME = "build_date_from_year_period"
SKIP_DIRS = {"target", "dbt_packages", "logs"}
SUFFIXES = (".sql", ".yml", ".yaml", ".md", ".py", ".jinja")


def _hits():
    found = []
    for dirpath, dirnames, files in os.walk(DBT):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for name in sorted(files):
            if not name.endswith(SUFFIXES):
                continue
            path = os.path.join(dirpath, name)
            with open(path, errors="replace") as f:
                for n, line in enumerate(f, 1):
                    if NAME in line:
                        found.append(f"{os.path.relpath(path, PROJECT_ROOT)}:{n}")
    return found


class NoMonthPeriodMacro(unittest.TestCase):
    def test_dbt_project_scanned(self):
        self.assertTrue(
            os.path.isfile(os.path.join(DBT, "macros", "declared_periods.sql")),
            "dbt_project/macros/declared_periods.sql not found: the scan would pass on nothing",
        )

    def test_no_build_date_from_year_period(self):
        hits = _hits()
        self.assertEqual(
            hits, [], f"{NAME} is named in {len(hits)} place(s); date periods from declared_periods(): {hits}"
        )


if __name__ == "__main__":
    unittest.main()
