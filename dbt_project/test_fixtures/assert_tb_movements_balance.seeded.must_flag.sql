-- gate: expect assert_tb_movements_balance flag 1
-- konsolidat#266 review: the standing must_flag fixture for assert_tb_movements_balance. Its konsol#255
-- red fixture now passes on the fixed model (assert_tb_movements_balance.split_pnl_close.sql), so this
-- one seeds silver_tb_movements' OUTPUT directly and runs the test alone. ZZE1 FY2026 P12 nets to
-- 100 - 90 = 10, not 0: exactly one entity-period is named.
INSERT INTO epm_silver.silver_tb_movements (data_area_id, fiscal_year, fiscal_period, main_account, amount_basis, movement_kind, source_net_amount, movement_amount) VALUES
  ('ZZE1', 2026, 12, 'ZZ4000', 'Period-end balance', 'activity', 100, 100),
  ('ZZE1', 2026, 12, 'ZZ3000', 'Period-end balance', 'year_end_close', -90, -90);
