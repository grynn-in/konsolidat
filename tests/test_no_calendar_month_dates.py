"""konsolidat#171 step 2d: no model or test builds a date from (year, period).

A period's date comes from the declared calendar (declared_periods(): start_date
/ end_date). The macro build_date_from_year_period gave the calendar month, which
is wrong for any fiscal year that does not start in January. The macro is gone;
this keeps it gone. CI runs the same check as a `git grep` step.
"""
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
NAME = "build_date_from_year_period"


class NoCalendarMonthDates(unittest.TestCase):
    def test_name_absent_from_dbt_project(self):
        hits = []
        for p in sorted((ROOT / "dbt_project").rglob("*")):
            if not p.is_file() or "target" in p.parts or "dbt_packages" in p.parts:
                continue
            try:
                lines = p.read_text(encoding="utf-8").splitlines()
            except (UnicodeDecodeError, OSError):
                continue
            hits += [f"{p.relative_to(ROOT)}:{i}" for i, l in enumerate(lines, 1) if NAME in l]
        self.assertEqual(hits, [], f"{NAME} must not appear under dbt_project (#171 2d)")


if __name__ == "__main__":
    unittest.main()
