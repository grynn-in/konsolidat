-- konsol#159 / konsolidat#175 re-review F2: two intercompany partners on one
-- account. Entity ZZF books intercompany revenue (ZZ4031) with two partners, ZZG
-- and ZZI, in FY2096 P1 and FY2097 P1, as claimed trial balance submissions.
-- Per year that is one account, -150 net, in two partner rows. The grain tests
-- (assert_ytd_trial_balance_grain, assert_prior_year_comparison_grain,
-- assert_partner_grain_not_fanned_out) need this shape to catch a partner that
-- fans out an account-grain model; nothing else in the test data has a partner.
-- Loaded and removed by tests/integration/test_dbt_build.py
-- (batch_id zzfix-ic2p-*).
--
-- konsolidat#227: this fixture is self-contained. It used to post for ZZF with
-- no entity row anywhere, so ZZF never resolved a currency and
-- assert_every_tb_entity_has_a_currency flagged it -- silver_entity_currencies
-- unions epm_staging.entities with silver_legal_entities and ZZF was in neither.
-- It also booked accounts it never declared. Its codes are its own: it shares
-- none with ic_decisions.sql, because the two load under separate pytest
-- fixtures and each tears down only what it created.

-- the three companies this fixture posts for, the seller and its two partners
INSERT INTO epm_staging.entities
    (data_area_id, entity_name, parent_entity, is_group, status, accounting_currency, country, erp_source)
VALUES
    ('ZZF', 'ZZF two-partner seller', '', 0, 'Active', 'USD', '', ''),
    ('ZZG', 'ZZG partner one', '', 0, 'Active', 'USD', '', ''),
    ('ZZI', 'ZZI partner two', '', 0, 'Active', 'USD', '', '');

-- the two accounts it books, in ZZCOA under its 'ZZ' root. is_retained_earnings
-- is 0 on both: ZZCOA already has exactly one year-end close account (ZZ3100),
-- and konsolidat#199 allows one per chart.
INSERT INTO epm_staging.main_accounts
    (main_account, account_name, chart_of_accounts, parent_account, is_group, account_type,
     statement_section, sub_section, normal_balance, time_balance, fx_method, is_posting,
     is_suspended, allow_ic, cf_category, cf_line_item, is_cash, main_account_category, status,
     is_retained_earnings)
VALUES
    ('ZZ1011', 'ZZF cash', 'ZZCOA', 'ZZ', 0, 'Asset', 'Balance Sheet', 'Current Assets', 'Debit', 'Balance', 'closing', 1, 0, 0, '', '', 1, 'CASH', 'Published', 0),
    ('ZZ4031', 'ZZF IC revenue', 'ZZCOA', 'ZZ', 0, 'Revenue', 'Profit and Loss', 'Revenue', 'Credit', 'Period', 'average', 1, 0, 1, '', '', 0, 'REVENUE', 'Published', 0);

-- the balance-sheet account needs a cash flow category (the relationships test
-- on gold_bs_movement.main_account)
INSERT INTO epm_staging.cash_flow_categories VALUES
    ('ZZ1011', 'Operating', 'Cash', 1, 'Published');

-- the calendar for the two years it books. Not optional for the same reason as
-- in ic_decisions.sql: without it these rows never reach the balance-sheet or
-- P&L views, and this fixture cannot rely on the other one declaring anything.
INSERT INTO epm_staging.fiscal_periods (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status) VALUES (2096,1,'FY2096-P01','P01 2096','Regular','2096-01-01','2096-01-31','Q1','Open'),(2096,13,'FY2096-P13','FY2096 closing','Closing','2096-12-31','2096-12-31','Q4','Open'),(2097,1,'FY2097-P01','P01 2097','Regular','2097-01-01','2097-01-31','Q1','Open'),(2097,13,'FY2097-P13','FY2097 closing','Closing','2097-12-31','2097-12-31','Q4','Open');

INSERT INTO epm_raw.trial_balance_submissions
    (batch_id, data_area_id, fiscal_year, fiscal_period, main_account,
     debit_amount, credit_amount, description, submission_name, submitted_at, partner_data_area_id)
VALUES
    ('zzfix-ic2p-2096', 'ZZF', 2096, 1, 'ZZ4031', 0, 100, 'IC sales', 'ZZFIX-2096', now(), 'ZZG'),
    ('zzfix-ic2p-2096', 'ZZF', 2096, 1, 'ZZ4031', 0, 50, 'IC sales', 'ZZFIX-2096', now(), 'ZZI'),
    ('zzfix-ic2p-2096', 'ZZF', 2096, 1, 'ZZ1011', 150, 0, 'cash', 'ZZFIX-2096', now(), ''),
    ('zzfix-ic2p-2097', 'ZZF', 2097, 1, 'ZZ4031', 0, 100, 'IC sales', 'ZZFIX-2097', now(), 'ZZG'),
    ('zzfix-ic2p-2097', 'ZZF', 2097, 1, 'ZZ4031', 0, 50, 'IC sales', 'ZZFIX-2097', now(), 'ZZI'),
    ('zzfix-ic2p-2097', 'ZZF', 2097, 1, 'ZZ1011', 150, 0, 'cash', 'ZZFIX-2097', now(), '');

INSERT INTO epm_raw.trial_balance_submission_control
    (batch_id, submission_name, data_area_id, fiscal_year, fiscal_period, row_count, claimed_at, amount_basis)
VALUES
    ('zzfix-ic2p-2096', 'ZZFIX-2096', 'ZZF', 2096, 1, 3, now(), 'Period movement'),
    ('zzfix-ic2p-2097', 'ZZFIX-2097', 'ZZF', 2097, 1, 3, now(), 'Period movement');
