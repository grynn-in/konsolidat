-- konsolidat#220: a reporting hierarchy whose members are dated. A member row is one tranche of a code, valid
-- from member_effective_from to member_effective_to (open = 2999-12-31); a renamed, moved or ended node is a
-- second tranche of the same code. The closure and every node model must resolve the tree as it was in a period.
--
-- Hierarchy ZZ_DIV over dim_business_unit:
--   ZZ_ROOT group 2010-01-01 .. open
--   ZZ_A    group 2010-01-01 .. 2024-12-31 "Alpha"      } a rename: two tranches of one code
--   ZZ_A    group 2025-01-01 .. open       "Alpha New"  }
--   ZZ_B    group 2010-01-01 .. open
--   ZZ_E    group 2017-01-01 .. 2024-12-31               (ended)
--   ZZ_G    group 2013-04-01 .. 2020-06-03               (disposed)
--   ZZ_EX   leaf under ZZ_E 2017-01-01 .. 2024-12-31    } a move: two tranches of one code
--   ZZ_EX   leaf under ZZ_B 2025-01-01 .. open          }
--   ZZ_GX   leaf under ZZ_G 2013-04-01 .. 2020-06-03
--   ZZ_AX   leaf under ZZ_A 2010-01-01 .. open
--
-- The live table may predate the two tranche columns: add them first.
ALTER TABLE epm_staging.reporting_hierarchies ADD COLUMN IF NOT EXISTS member_effective_from Date DEFAULT '1900-01-01';
ALTER TABLE epm_staging.reporting_hierarchies ADD COLUMN IF NOT EXISTS member_effective_to Date DEFAULT '2999-12-31';
INSERT INTO epm_staging.reporting_hierarchies
  (hierarchy_name, dimension, member_code, member_label, parent_member_code, is_group, hierarchy_level, path, effective_from, effective_to, is_default, status, member_effective_from, member_effective_to)
VALUES
  ('ZZ_DIV', 'dim_business_unit', 'ZZ_ROOT', 'ZZ root', '', 1, 1, 'ZZ_ROOT', '', '', 1, 'Published', '2010-01-01', '2999-12-31'),
  ('ZZ_DIV', 'dim_business_unit', 'ZZ_A', 'Alpha', 'ZZ_ROOT', 1, 2, 'ZZ_ROOT/ZZ_A', '', '', 1, 'Published', '2010-01-01', '2024-12-31'),
  ('ZZ_DIV', 'dim_business_unit', 'ZZ_A', 'Alpha New', 'ZZ_ROOT', 1, 2, 'ZZ_ROOT/ZZ_A', '', '', 1, 'Published', '2025-01-01', '2999-12-31'),
  ('ZZ_DIV', 'dim_business_unit', 'ZZ_B', 'ZZ B', 'ZZ_ROOT', 1, 2, 'ZZ_ROOT/ZZ_B', '', '', 1, 'Published', '2010-01-01', '2999-12-31'),
  ('ZZ_DIV', 'dim_business_unit', 'ZZ_E', 'ZZ E', 'ZZ_ROOT', 1, 2, 'ZZ_ROOT/ZZ_E', '', '', 1, 'Published', '2017-01-01', '2024-12-31'),
  ('ZZ_DIV', 'dim_business_unit', 'ZZ_G', 'ZZ G', 'ZZ_ROOT', 1, 2, 'ZZ_ROOT/ZZ_G', '', '', 1, 'Published', '2013-04-01', '2020-06-03'),
  ('ZZ_DIV', 'dim_business_unit', 'ZZ_EX', 'ZZ EX', 'ZZ_E', 0, 3, 'ZZ_ROOT/ZZ_E/ZZ_EX', '', '', 1, 'Published', '2017-01-01', '2024-12-31'),
  ('ZZ_DIV', 'dim_business_unit', 'ZZ_EX', 'ZZ EX', 'ZZ_B', 0, 3, 'ZZ_ROOT/ZZ_B/ZZ_EX', '', '', 1, 'Published', '2025-01-01', '2999-12-31'),
  ('ZZ_DIV', 'dim_business_unit', 'ZZ_GX', 'ZZ GX', 'ZZ_G', 0, 3, 'ZZ_ROOT/ZZ_G/ZZ_GX', '', '', 1, 'Published', '2013-04-01', '2020-06-03'),
  ('ZZ_DIV', 'dim_business_unit', 'ZZ_AX', 'ZZ AX', 'ZZ_A', 0, 3, 'ZZ_ROOT/ZZ_A/ZZ_AX', '', '', 1, 'Published', '2010-01-01', '2999-12-31');
