-- gate: build +assert_declared_historical_has_a_rate
-- gate: expect assert_declared_historical_has_a_rate pass
-- assert_declared_historical_has_a_rate, April fiscal year (konsolidat#189 PR3, konsol#348 QA2 c): must PASS
-- once the test dates a period by its DECLARED window_end_date. FY2025 runs Apr 2025 - Mar 2026, so P1 is
-- 2025-04-01 .. 2025-04-30 and P2 is May 2025. ZZ3000's only Historical Equity Rate is dated 2025-04-15: it covers
-- P1 (declared end 2025-04-30). The macro build_date_from_year_period() dates P1 at 2025-01-01, before the
-- tranche, so a test reading the macro names P1 as a gap although a rate covers it (red on the old test).
-- ZZ3100's tranche (2024-01-01) covers both periods. Expected: nothing flagged.
--
-- The gate creates every warehouse table this file names in its scratch schemas with the live DDL.
-- The lineage of gold_consolidated_trial_balance also reads these ERP-side tables, empty on a
-- trial-balance-only site, so they are named here to exist (empty):
-- epm_raw.general_journal_account_entry_bi_entities, epm_raw.general_journal_entry_bi_entities,
-- epm_raw.ledgers, epm_raw.legal_entities, epm_raw.fiscal_calendar_years,
-- epm_gold.entity_fiscal_calendars, epm_staging.dimension_mappings.
--
-- The live tables may predate these three columns: add them to the scratch clones first.
ALTER TABLE epm_staging.historical_equity_rates ADD COLUMN IF NOT EXISTS to_currency LowCardinality(String);
ALTER TABLE epm_raw.trial_balance_submission_control ADD COLUMN IF NOT EXISTS amount_basis String DEFAULT '';
ALTER TABLE epm_staging.main_accounts ADD COLUMN IF NOT EXISTS is_retained_earnings UInt8 DEFAULT 0;
INSERT INTO epm_staging.main_accounts
  (main_account, account_name, chart_of_accounts, parent_account, is_group, account_type, statement_section, sub_section, normal_balance, time_balance, fx_method, is_posting, is_suspended, allow_ic, cf_category, cf_line_item, is_cash, main_account_category, status, is_retained_earnings)
VALUES
  ('ZZ1000', 'ZZ cash', 'ZZCOA', '', 0, 'Asset', 'Balance Sheet', 'Current Assets', 'Debit', 'Balance', 'closing', 1, 0, 0, '', '', 1, 'CASH', 'Published', 0),
  ('ZZ3000', 'ZZ share capital', 'ZZCOA', '', 0, 'Equity', 'Balance Sheet', 'Equity', 'Credit', 'Balance', 'historical', 1, 0, 0, '', '', 0, 'EQUITY', 'Published', 0),
  ('ZZ3100', 'ZZ retained earnings', 'ZZCOA', '', 0, 'Equity', 'Balance Sheet', 'Equity', 'Credit', 'Balance', 'historical', 1, 0, 0, '', '', 0, 'EQUITY', 'Published', 0);
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2025, 1, 'FY2025-P01', 'Apr 2025', 'Regular', '2025-04-01', '2025-04-30', 'Q1', 'Open'),
  (2025, 2, 'FY2025-P02', 'May 2025', 'Regular', '2025-05-01', '2025-05-31', 'Q1', 'Open');
INSERT INTO epm_staging.entities
  (data_area_id, entity_name, parent_entity, is_group, status, accounting_currency, country, erp_source)
VALUES
  ('ZZOP', 'ZZ Operating', 'ZZGRP', 0, 'Active', 'EUR', 'DE', '');
INSERT INTO epm_gold.consolidation_groups
  (consolidation_group, data_area_id, entity_name, reporting_currency)
VALUES
  ('ZZGRP', '', 'ZZ Group', 'USD'),
  ('ZZGRP', 'ZZOP', 'ZZ Operating', 'USD');
INSERT INTO epm_staging.consolidation_hierarchy
  (consolidation_group, data_area_id, parent_group, hierarchy_level, path)
VALUES
  ('ZZGRP', 'ZZOP', '', 1, 'ZZGRP');
INSERT INTO epm_staging.consolidation_ancestry
  (consolidation_group, data_area_id, link_group, link_data_area_id, link_depth, depth, path)
VALUES
  ('ZZGRP', 'ZZOP', 'ZZGRP', 'ZZOP', 1, 1, 'ZZGRP/ZZOP');
INSERT INTO epm_staging.ownership_periods
  (consolidation_group, data_area_id, effective_date, ownership_pct, consolidation_method)
VALUES
  ('ZZGRP', 'ZZOP', '2020-01-01', 100, 'full');
-- usd_log10 is required, not decorative: it defaults to nan, and a currency with no
-- reference magnitude makes assert_governed_rate_sane warn on every rate that uses it
-- (macros/fx_magnitude.sql). USD is 0 by definition; EUR is log10(EUR units per 1 USD).
-- A 0 on anything but USD reads as unset, so EUR carries a real non-zero value.
INSERT INTO epm_gold.currencies
  (currency_code, currency_name, symbol, minor_unit, usd_log10)
VALUES
  ('EUR', 'Euro', 'E', 2, -0.05),
  ('USD', 'US Dollar', '$', 2, 0);
INSERT INTO epm_staging.group_exchange_rates
  (to_currency, from_currency, fiscal_year, fiscal_period, rate_type, rate, document)
VALUES
  ('USD', 'EUR', 2025, 1, 'Closing', 1.10, 'ZZ-GER-2025-01'),
  ('USD', 'EUR', 2025, 1, 'Average', 1.05, 'ZZ-GER-2025-01'),
  ('USD', 'EUR', 2025, 2, 'Closing', 1.20, 'ZZ-GER-2025-02'),
  ('USD', 'EUR', 2025, 2, 'Average', 1.15, 'ZZ-GER-2025-02');
-- The rates themselves, keyed (consolidation_group, data_area_id, main_account, to_currency) on the
-- entity's OWNING group and the consolidating group's presentation currency (konsol#374). ZZ3000's
-- only tranche starts in P2, so P1 resolves to no rate; ZZ3100's predates both periods, so neither
-- of its periods may be named.
INSERT INTO epm_staging.historical_equity_rates
  (consolidation_group, data_area_id, main_account, rate_date, historical_rate, to_currency)
VALUES
  ('ZZGRP', 'ZZOP', 'ZZ3000', '2025-04-15', 1.30, 'USD'),
  ('ZZGRP', 'ZZOP', 'ZZ3100', '2025-01-01', 1.10, 'USD');
INSERT INTO epm_raw.trial_balance_submissions
  (batch_id, data_area_id, fiscal_year, fiscal_period, main_account, debit_amount, credit_amount, description, submission_name, submitted_at, partner_data_area_id)
VALUES
  ('ZZB1', 'ZZOP', 2025, 1, 'ZZ1000', 300, 0, 'Cash', 'ZZ-TBS-1', now(), ''),
  ('ZZB1', 'ZZOP', 2025, 1, 'ZZ3000', 0, 200, 'Share capital', 'ZZ-TBS-1', now(), ''),
  ('ZZB1', 'ZZOP', 2025, 1, 'ZZ3100', 0, 100, 'Retained earnings', 'ZZ-TBS-1', now(), ''),
  ('ZZB2', 'ZZOP', 2025, 2, 'ZZ1000', 90, 0, 'Cash', 'ZZ-TBS-2', now(), ''),
  ('ZZB2', 'ZZOP', 2025, 2, 'ZZ3000', 0, 50, 'Share capital', 'ZZ-TBS-2', now(), ''),
  ('ZZB2', 'ZZOP', 2025, 2, 'ZZ3100', 0, 40, 'Retained earnings', 'ZZ-TBS-2', now(), '');
INSERT INTO epm_raw.trial_balance_submission_control
  (batch_id, submission_name, data_area_id, fiscal_year, fiscal_period, row_count, claimed_at, amount_basis)
VALUES
  ('ZZB1', 'ZZ-TBS-1', 'ZZOP', 2025, 1, 3, now(), 'Period movement'),
  ('ZZB2', 'ZZ-TBS-2', 'ZZOP', 2025, 2, 3, now(), 'Period movement');
