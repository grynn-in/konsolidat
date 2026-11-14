"""The replica's period_date is the declared period END (konsolidat#171 2d), as the warehouse's period_date."""
import datetime as dt
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import aquila_bike_offline as ab  # noqa: E402


class PeriodDate(unittest.TestCase):
    def test_period_is_its_last_day(self):
        self.assertEqual(ab.Offline.period_date((2024, 2)), dt.date(2024, 2, 29))
        self.assertEqual(ab.Offline.period_date((2025, 6)), dt.date(2025, 6, 30))
        self.assertEqual(ab.Offline.period_date((2024, 12)), dt.date(2024, 12, 31))

    def test_closing_period_ends_with_period_12(self):
        self.assertEqual(ab.Offline.period_date((2024, 13)), dt.date(2024, 12, 31))

    def test_opening_period_is_the_prior_year_end(self):
        # the ownership window reads an Opening P0 at the last day of the prior year (declared_periods window_end_date)
        self.assertEqual(ab.Offline.period_date((2024, 0)), dt.date(2023, 12, 31))


if __name__ == "__main__":
    unittest.main()
