-- gate: expect assert_tb_movements_difference_within_dimension flag 1
-- konsolidat#266 review: the standing must_flag fixture for this test. Its konsol#255 red fixture
-- now passes on the fixed model (assert_tb_movements_difference_within_dimension.sql), so this one
-- seeds silver_tb_movements' OUTPUT directly and runs the test alone. ZZ1000 is split across CC1
-- and CC2. P2's CC2 slice (balance 30) was differenced against CC1's P1 balance (100) and reads
-- -70; within CC2 there is no earlier balance, so its movement is 30. One row, difference -100.
-- CC1 at P1 differences against nothing and is right (100): not named.
INSERT INTO epm_silver.silver_tb_movements (data_area_id, fiscal_year, fiscal_period, main_account, partner_data_area_id, dim_business_unit, dim_cost_center, dim_department, amount_basis, movement_kind, source_net_amount, movement_amount) VALUES
  ('ZZE1', 2026, 1, 'ZZ1000', '', '', 'CC1', '', 'Period-end balance', 'activity', 100, 100),
  ('ZZE1', 2026, 2, 'ZZ1000', '', '', 'CC2', '', 'Period-end balance', 'activity', 30, -70);
