-- C2 / grynn-in/konsolidat#120: IAS-21 equity-translation coverage guard.
--
-- History: #120 had two asks, both fixed at the time in the demo data and its
-- generator via #104/#121. Both have since been removed; this note is a record only.
--   (a) add missing IAS-21 equity-translation coverage for one group's entities, and
--   (b) drop/quarantine 12 acquisition-date `exchange_rates` rows that no model
--       consumes (equity translation reads `historical_equity_rates`, NOT the
--       `exchange_rates` table — see gold_consolidated_trial_balance `historical_rates`
--       CTE / the ASOF `hr` join on (consolidation_group, data_area_id, main_account)).
-- What remains is this gate. It encodes the invariant as a source contract (no model
-- SQL changes, so full builds are byte-for-byte unchanged) and returns one offender
-- row per violation:
--
--   missing_equity_rate_coverage — an entity node in `consolidation_groups` has NO
--       `historical_equity_rates` row, so its equity accounts silently fall back to
--       the closing rate instead of the acquisition rate. It also catches rates keyed
--       to a consolidation group that the join never matches (a #104-review bug).
--
--   orphan_equity_rate — a `historical_equity_rates` (group, entity) that matches no
--       entity node in `consolidation_groups`: a dead rate no model can reference (the
--       #120(b) guard — a mis-keyed equity rate is the same dead weight the dropped
--       acquisition-date FX rows were).
--
-- GREEN requires `historical_equity_rates` to cover every entity node in
-- `consolidation_groups` (every node with data_area_id != '', parent entity
-- included). konsol writes those rows when a Historical Equity Rate is submitted.
-- The equity rate join is inert on real-D365 gold (no 3010/3100 equity accounts), so
-- correcting the source never moves gold row counts.

{# F2: the seed is deleted; this reads the structure table konsol writes. The
   data_area_id != '' guard drops group nodes, which the seed never carried —
   without it every group node would read as an entity with no equity rate. #}
with seed_entities as (
    select consolidation_group, data_area_id
    from {{ source('epm_gold', 'consolidation_groups') }}
    where data_area_id != ''
),

rates as (
    select distinct consolidation_group, data_area_id
    from {{ source('epm_staging', 'historical_equity_rates') }}
)

select
    consolidation_group,
    data_area_id,
    'missing_equity_rate_coverage' as reason
from seed_entities
where (consolidation_group, data_area_id) not in (
    select consolidation_group, data_area_id from rates
)

union all

select
    consolidation_group,
    data_area_id,
    'orphan_equity_rate' as reason
from rates
where (consolidation_group, data_area_id) not in (
    select consolidation_group, data_area_id from seed_entities
)
