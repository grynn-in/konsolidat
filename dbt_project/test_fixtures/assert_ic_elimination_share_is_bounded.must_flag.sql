-- konsolidat#245. Rows assert_ic_elimination_share_is_bounded MUST flag.
--
-- The red evidence for this test, committed rather than quoted in a commit
-- message. Three rounds of fixes on this layer shipped tests that could not
-- fail, and the red runs existed only as prose. This is the project's
-- convention for that (test_fixtures/README.md) and it should have been here
-- from the first round.
--
-- The case: one intercompany control account carrying TWO legs of very
-- different sizes. IC:SMALL's leg is 1, and its slices have been magnified to
-- 100,000x. Keyed on the account alone — which is what the first two versions
-- of this test did — max() compares 100,000 against IC:BIG's 5,000,000 and
-- sees nothing. Keyed per leg (journal_id), IC:SMALL is caught and IC:BIG is
-- left alone.
--
-- Load against the test and it must return exactly one row, for IC:SMALL.
INSERT INTO epm_gold.gold_ic_eliminations
    (consolidation_group, fiscal_year, fiscal_period, rule_id, elimination_view,
     elimination_kind, debit_entity, credit_entity, debit_account, credit_account,
     elimination_amount, debit_elimination, credit_elimination)
VALUES
    ('ZZG', 2026, 6, 'IC:BIG',   'group', 'balance', 'ZZA', 'ZZB', 'ZZCTRL', 'ZZCTRL2',
     5000000, -5000000, 5000000),
    ('ZZG', 2026, 6, 'IC:SMALL', 'group', 'balance', 'ZZA', 'ZZC', 'ZZCTRL', 'ZZCTRL3',
     1, -1, 1);

-- IC:BIG, apportioned legitimately: no slice exceeds its own leg.
INSERT INTO epm_gold.gold_fully_consolidated_tb
    (consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account,
     account_name, reporting_currency, amount, adjustment_type, journal_id)
VALUES
    ('ZZG', '', 2026, 6, 'ZZCTRL', 'IC Elimination', '', -3000000, 'ic_elimination', 'IC:BIG'),
    ('ZZG', '', 2026, 6, 'ZZCTRL', 'IC Elimination', '', -2000000, 'ic_elimination', 'IC:BIG');

-- IC:SMALL, magnified 100,000x. Sums to its leg of -1, so every total-based
-- check passes; keyed on the account it hides behind IC:BIG.
INSERT INTO epm_gold.gold_fully_consolidated_tb
    (consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account,
     account_name, reporting_currency, amount, adjustment_type, journal_id)
VALUES
    ('ZZG', '', 2026, 6, 'ZZCTRL', 'IC Elimination', '', -100000, 'ic_elimination', 'IC:SMALL'),
    ('ZZG', '', 2026, 6, 'ZZCTRL', 'IC Elimination', '',   99999, 'ic_elimination', 'IC:SMALL');
