-- gate: expect assert_year_end_close_invents_no_movement flag 1
-- konsolidat#266 review: the standing must_flag fixture for this test. Its konsol#255 red fixture
-- now passes on the fixed model (assert_year_end_close_invents_no_movement.sql), so this one seeds
-- silver_tb_movements' OUTPUT and silver_main_accounts directly and runs the test alone.
-- FY2026 P13 close rows: ZZ1000 (balance sheet, not retained earnings) moves +50, an invented
-- movement, so it is named. ZZ4000 is P&L (the close is meant to move it) and ZZ3000 is the
-- retained-earnings account with no partner (the close's target): neither is named. One row.
INSERT INTO epm_silver.silver_tb_movements (data_area_id, fiscal_year, fiscal_period, main_account, partner_data_area_id, amount_basis, movement_kind, source_net_amount, movement_amount) VALUES
  ('ZZE1', 2026, 13, 'ZZ1000', '', 'Period-end balance', 'year_end_close', 150, 50),
  ('ZZE1', 2026, 13, 'ZZ4000', '', 'Period-end balance', 'year_end_close', 0, -100),
  ('ZZE1', 2026, 13, 'ZZ3000', '', 'Period-end balance', 'year_end_close', -50, 50);
INSERT INTO epm_silver.silver_main_accounts (main_account_id, is_pnl, is_retained_earnings) VALUES ('ZZ1000', 0, 0), ('ZZ4000', 1, 0), ('ZZ3000', 0, 1);
