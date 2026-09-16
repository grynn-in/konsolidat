-- assert_declared_historical_has_a_rate: must FLAG exactly one (entity, account, period).
-- konsolidat#218: the retained-earnings account DECLARES its translation method. A customer who
-- declares fx_method = 'historical' is expected to supply Historical Equity Rates for it; when a
-- period is not covered, gold_consolidated_trial_balance's ASOF join yields no rate and the `case`
-- falls back to the closing rate, with nobody told which account or which period.
--
-- The rate is resolved AS-OF the period: the latest tranche whose rate_date <= period_date, keyed
-- (owner group, entity, account). A period BEFORE the first tranche therefore has no rate at all --
-- the case the ASOF join was fixed for (konsolidat#92 finding 2, where the old row_number()/rn=1
-- join borrowed a future tranche's rate instead).
--
-- One ZZ entity (ZZOP, EUR) in a USD group (ZZGRP), FY2026 periods 1 and 2, period movements:
--   ZZ1000 asset,  closing     -- not declared historical, never a candidate
--   ZZ3000 equity, historical  -- rate tranche starts 2026-02-01, i.e. P2 ONLY
--   ZZ3100 equity, historical  -- rate tranche from 2025-01-01, covers BOTH periods
-- period_date = build_date_from_year_period(): P1 -> 2026-01-01, P2 -> 2026-02-01.
-- So ZZ3000's own tranche (2026-02-01) covers P2 and NOT P1.
--
-- Expected: exactly ONE flagged row -- ZZGRP / ZZOP / ZZ3000 / FY2026 P1. It must name the EARLIER
-- period and not the later one (P2 is covered by the same account's tranche), and ZZ3100 must not
-- appear at all in either period.
--
-- The gate creates every warehouse table this file names in its scratch schemas with the live DDL.
-- The lineage of gold_consolidated_trial_balance also reads these ERP-side tables, empty on a
-- trial-balance-only site, so they are named here to exist (empty):
-- epm_raw.general_journal_account_entry_bi_entities, epm_raw.general_journal_entry_bi_entities,
-- epm_raw.ledgers, epm_raw.legal_entities, epm_raw.fiscal_calendar_years,
-- epm_gold.entity_fiscal_calendars, epm_staging.dimension_mappings.
--
-- The live tables may predate these two columns: add them to the scratch clones first.
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
  (2026, 1, 'FY2026-P01', 'Jan 2026', 'Regular', '2026-01-01', '2026-01-31', 'Q1', 'Open'),
  (2026, 2, 'FY2026-P02', 'Feb 2026', 'Regular', '2026-02-01', '2026-02-28', 'Q1', 'Open');
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
  ('USD', 'EUR', 2026, 1, 'Closing', 1.10, 'ZZ-GER-2026-01'),
  ('USD', 'EUR', 2026, 1, 'Average', 1.05, 'ZZ-GER-2026-01'),
  ('USD', 'EUR', 2026, 2, 'Closing', 1.20, 'ZZ-GER-2026-02'),
  ('USD', 'EUR', 2026, 2, 'Average', 1.15, 'ZZ-GER-2026-02');
-- The rates themselves, keyed (consolidation_group, data_area_id, main_account) on the entity's
-- OWNING group. ZZ3000's only tranche starts in P2, so P1 resolves to no rate; ZZ3100's predates
-- both periods, so neither of its periods may be named.
INSERT INTO epm_staging.historical_equity_rates
  (consolidation_group, data_area_id, main_account, rate_date, historical_rate)
VALUES
  ('ZZGRP', 'ZZOP', 'ZZ3000', '2026-02-01', 1.30),
  ('ZZGRP', 'ZZOP', 'ZZ3100', '2025-01-01', 1.10);
INSERT INTO epm_raw.trial_balance_submissions
  (batch_id, data_area_id, fiscal_year, fiscal_period, main_account, debit_amount, credit_amount, description, submission_name, submitted_at, partner_data_area_id)
VALUES
  ('ZZB1', 'ZZOP', 2026, 1, 'ZZ1000', 300, 0, 'Cash', 'ZZ-TBS-1', now(), ''),
  ('ZZB1', 'ZZOP', 2026, 1, 'ZZ3000', 0, 200, 'Share capital', 'ZZ-TBS-1', now(), ''),
  ('ZZB1', 'ZZOP', 2026, 1, 'ZZ3100', 0, 100, 'Retained earnings', 'ZZ-TBS-1', now(), ''),
  ('ZZB2', 'ZZOP', 2026, 2, 'ZZ1000', 90, 0, 'Cash', 'ZZ-TBS-2', now(), ''),
  ('ZZB2', 'ZZOP', 2026, 2, 'ZZ3000', 0, 50, 'Share capital', 'ZZ-TBS-2', now(), ''),
  ('ZZB2', 'ZZOP', 2026, 2, 'ZZ3100', 0, 40, 'Retained earnings', 'ZZ-TBS-2', now(), '');
INSERT INTO epm_raw.trial_balance_submission_control
  (batch_id, submission_name, data_area_id, fiscal_year, fiscal_period, row_count, claimed_at, amount_basis)
VALUES
  ('ZZB1', 'ZZ-TBS-1', 'ZZOP', 2026, 1, 3, now(), 'Period movement'),
  ('ZZB2', 'ZZ-TBS-2', 'ZZOP', 2026, 2, 3, now(), 'Period movement');
