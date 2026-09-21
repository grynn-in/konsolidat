-- Must-flag fixture for assert_equity_rate_coverage (konsolidat#232).
--
-- The check asks for a historical equity rate only where the model applies one:
-- the entity holds a balance on an account the chart marks fx_method='historical',
-- and its functional currency differs from the group's reporting currency.
--
-- These rows are the ZZ fixture with one change: ZZOP is EUR-functional, not USD.
-- It holds ZZ3000 (Common stock, fx_method 'historical') and has no
-- historical_equity_rates row, so the test must flag exactly:
--     ZZGRP  ZZOP  missing_equity_rate_coverage
--
-- Swap the entity currency back to 'USD' and the same rows must PASS — a
-- USD-functional entity in a USD group has no translation to get wrong. That
-- pair is the point of the fixture: the currency is what decides, not the
-- presence of equity alone.

INSERT INTO epm_staging.main_accounts (main_account, account_name, chart_of_accounts, parent_account, is_group, account_type, statement_section, sub_section, normal_balance, time_balance, fx_method, is_posting, is_suspended, allow_ic, cf_category, cf_line_item, is_cash, main_account_category, status, is_retained_earnings) VALUES
('ZZ', 'ZZ group chart', 'ZZCOA', '', 1, '', '', '', '', '', '', 0, 0, 0, '', '', 0, '', 'Published', 0),
('ZZ1000', 'ZZ cash', 'ZZCOA', 'ZZ', 0, 'Asset', 'Balance Sheet', 'Current Assets', 'Debit', 'Balance', 'closing', 1, 0, 0, '', '', 1, 'CASH', 'Published', 0),
('ZZ3000', 'ZZ share capital', 'ZZCOA', 'ZZ', 0, 'Equity', 'Balance Sheet', 'Equity', 'Credit', 'Balance', 'historical', 1, 0, 0, '', '', 0, 'EQUITY', 'Published', 0),
('ZZ3100', 'ZZ retained earnings', 'ZZCOA', 'ZZ', 0, 'Equity', 'Balance Sheet', 'Equity', 'Credit', 'Balance', 'closing', 1, 0, 0, '', '', 0, 'EQUITY', 'Published', 1),
('ZZ4000', 'ZZ revenue', 'ZZCOA', 'ZZ', 0, 'Revenue', 'Profit and Loss', 'Revenue', 'Credit', 'Period', 'average', 1, 0, 0, '', '', 0, 'REVENUE', 'Published', 0);

INSERT INTO epm_staging.cash_flow_categories VALUES
('ZZ1000', 'Operating', 'Cash', 1, 'Published'),
('ZZ3000', 'Financing', 'Share capital', 0, 'Published'),
('ZZ3100', 'Financing', 'Retained earnings', 0, 'Published');

-- EUR, not USD: this is the single difference from the passing fixture.
INSERT INTO epm_staging.entities VALUES ('ZZOP', 'ZZ Operating', 'ZZGRP', 0, 'Active', 'EUR', 'DE', '');

INSERT INTO epm_staging.fiscal_periods (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status) VALUES
(2026, 1, 'FY2026-P01', 'Jan 2026', 'Regular', '2026-01-01', '2026-01-31', 'Q1', 'Open'),
(2026, 13, 'FY2026-P13', 'FY2026 closing', 'Closing', '2026-12-31', '2026-12-31', 'Q4', 'Open');

-- The group reports in USD, so an EUR entity must be translated.
INSERT INTO epm_gold.consolidation_groups (consolidation_group, data_area_id, entity_name, reporting_currency) VALUES
('ZZGRP', '', 'ZZ Group', 'USD'),
('ZZGRP', 'ZZOP', 'ZZ Operating', 'USD');

INSERT INTO epm_staging.consolidation_hierarchy (consolidation_group, data_area_id, parent_group, hierarchy_level, path) VALUES
('ZZGRP', 'ZZOP', '', 1, 'ZZGRP');

INSERT INTO epm_staging.consolidation_ancestry VALUES ('ZZGRP', 'ZZOP', 'ZZGRP', 'ZZOP', 1, 1, 'ZZGRP/ZZOP');

INSERT INTO epm_staging.ownership_periods (consolidation_group, data_area_id, effective_date, ownership_pct, consolidation_method) VALUES
('ZZGRP', 'ZZOP', '2020-01-01', 100, 'full');

INSERT INTO epm_gold.currencies VALUES ('USD', 'US Dollar', '$', 2, 0);

INSERT INTO epm_gold.scenario_definitions (scenario_id, scenario_name, scenario_type, is_active) VALUES
('ACTUAL', 'Actual', 'actual', 1), ('BUDGET', 'Budget', 'budget', 1), ('FORECAST', 'Forecast', 'forecast', 1);

-- ZZ3000 carries a non-zero balance: equity that has to be translated somehow.
INSERT INTO epm_raw.trial_balance_submissions (batch_id, data_area_id, fiscal_year, fiscal_period, main_account, debit_amount, credit_amount, description, submission_name, submitted_at) VALUES
('ZZB1', 'ZZOP', 2026, 1, 'ZZ1000', 150, 0, '', 'ZZ-TBS-1', now()),
('ZZB1', 'ZZOP', 2026, 1, 'ZZ3000', 0, 50, '', 'ZZ-TBS-1', now()),
('ZZB1', 'ZZOP', 2026, 1, 'ZZ4000', 0, 100, '', 'ZZ-TBS-1', now());

INSERT INTO epm_raw.trial_balance_submission_control (batch_id, submission_name, data_area_id, fiscal_year, fiscal_period, row_count, claimed_at, amount_basis) VALUES
('ZZB1', 'ZZ-TBS-1', 'ZZOP', 2026, 1, 3, now(), 'Period movement');

-- Deliberately no INSERT INTO epm_staging.historical_equity_rates: that absence
-- is what the test must catch.
