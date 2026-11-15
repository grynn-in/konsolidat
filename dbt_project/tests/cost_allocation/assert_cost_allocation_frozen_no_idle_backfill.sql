-- The hop_kind backfill is a mutation, and a mutation rewrites parts: it must run only
-- when a blank hop_kind exists (konsol#269, RF8). Rows returned are violations: a
-- backfill UPDATE recorded against the frozen table when the table held no blank
-- hop_kind before the build. Only the fixture gate can know that, so the test is
-- enabled only under it; on a real site the table's history legitimately holds one
-- (the upgrade), and the test would fail for no fault.
{{ config(enabled=var('cost_allocation_fixture_values', false)) }}
select command
from system.mutations
where database = '{{ ref("gold_cost_allocation_frozen").schema }}'
  and table = '{{ ref("gold_cost_allocation_frozen").identifier }}'
  and command like '%UPDATE hop_kind%'
