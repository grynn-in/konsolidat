-- konsol#159 / konsolidat#175 re-review F2: two intercompany partners on one
-- account. Entity ZZF books intercompany revenue (4030) with two partners, ZZG
-- and ZZH, in FY2096 P1 and FY2097 P1, as claimed trial balance submissions.
-- Per year that is one account, -150 net, in two partner rows. The grain tests
-- (assert_ytd_trial_balance_grain, assert_prior_year_comparison_grain,
-- assert_partner_grain_not_fanned_out) need this shape to catch a partner that
-- fans out an account-grain model; nothing else in the test data has a partner.
-- Loaded and removed by tests/integration/test_dbt_build.py
-- (batch_id zzfix-ic2p-*).
INSERT INTO epm_raw.trial_balance_submissions
    (batch_id, data_area_id, fiscal_year, fiscal_period, main_account,
     debit_amount, credit_amount, description, submission_name, submitted_at, partner_data_area_id)
VALUES
    ('zzfix-ic2p-2096', 'ZZF', 2096, 1, '4030', 0, 100, 'IC sales', 'ZZFIX-2096', now(), 'ZZG'),
    ('zzfix-ic2p-2096', 'ZZF', 2096, 1, '4030', 0, 50, 'IC sales', 'ZZFIX-2096', now(), 'ZZH'),
    ('zzfix-ic2p-2096', 'ZZF', 2096, 1, '1010', 150, 0, 'cash', 'ZZFIX-2096', now(), ''),
    ('zzfix-ic2p-2097', 'ZZF', 2097, 1, '4030', 0, 100, 'IC sales', 'ZZFIX-2097', now(), 'ZZG'),
    ('zzfix-ic2p-2097', 'ZZF', 2097, 1, '4030', 0, 50, 'IC sales', 'ZZFIX-2097', now(), 'ZZH'),
    ('zzfix-ic2p-2097', 'ZZF', 2097, 1, '1010', 150, 0, 'cash', 'ZZFIX-2097', now(), '');

INSERT INTO epm_raw.trial_balance_submission_control
    (batch_id, submission_name, data_area_id, fiscal_year, fiscal_period, row_count, claimed_at, amount_basis)
VALUES
    ('zzfix-ic2p-2096', 'ZZFIX-2096', 'ZZF', 2096, 1, 3, now(), 'Period movement'),
    ('zzfix-ic2p-2097', 'ZZFIX-2097', 'ZZF', 2097, 1, 3, now(), 'Period movement');
