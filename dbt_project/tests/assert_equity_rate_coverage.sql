-- C2 / grynn-in/konsolidat#120: IAS-21 equity-translation coverage guard.
--
-- #120 had two asks, both already landed in the demo-data generator via #104/#121:
--   (a) add the missing AMG IAS-21 equity-translation coverage, and
--   (b) drop/quarantine the 12 acquisition-date `exchange_rates` rows that no model
--       consumes (equity translation reads `historical_equity_rates`, NOT the
--       `exchange_rates` table — see gold_consolidated_trial_balance `historical_rates`
--       CTE / the ASOF `hr` join on (consolidation_group, data_area_id, main_account)).
-- The genuinely-missing piece is this TDD gate. It encodes the invariant as a
-- source/seed contract (no model SQL changes, so full builds are byte-for-byte
-- unchanged) and returns one offender row per violation:
--
--   missing_equity_rate_coverage — a `consolidation_groups` seed subsidiary has NO
--       `historical_equity_rates` row, so its equity accounts silently fall back to
--       the closing rate instead of the acquisition rate. This is the #120 "AMG
--       entities have equity-translation coverage" check (AMHQ/AMUS/AMDE), and it
--       also catches the #104-review bug where Contoso DEMF/GBMF rates were keyed to
--       a `GROUP_EMEA` group the GROUP_CORP-seeded join never matched.
--
--   orphan_equity_rate — a `historical_equity_rates` (group, entity) that matches no
--       seed subsidiary: a dead rate no model can reference (the #120(b) "no model
--       references the dropped/re-homed rows" guard — a mis-keyed equity rate is the
--       same dead weight the dropped acquisition-date FX rows were).
--
-- GREEN requires `historical_equity_rates` to cover exactly the seed subsidiaries
-- (origin/main demo-data: GROUP_CORP×{USMF,DEMF,GBMF,JPMF} + AMG×{AMHQ,AMUS,AMDE}).
-- The equity rate join is inert on real-D365 gold (no 3010/3100 equity accounts), so
-- correcting the source never moves gold row counts.

with seed_entities as (
    select consolidation_group, data_area_id
    from {{ ref('consolidation_groups') }}
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
