{{
    config(
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# Scenario metadata from konsol's Scenario doctype, plus any created through
   the API. konsolidat#146: the first half read `ref('scenario_definitions')`, a
   seed that materialised into epm_gold.scenario_definitions — the same relation
   konsol writes — so `dbt seed` and `bench migrate` overwrote each other, and
   the row labelled 'seed' was in fact whichever of the two had run last. It is
   labelled for what it is now. The doctype held 17 scenarios where the CSV held
   4, two of them under stale names. #}
select
    scenario_id,
    scenario_name,
    scenario_type,
    is_active,
    'konsol' as source
from {{ source('epm_gold', 'scenario_definitions') }}

union all

select
    scenario_id,
    scenario_name,
    scenario_type,
    is_active,
    'api' as source
from {{ source('epm_staging', 'scenario_definitions') }}
where scenario_id not in (
    select scenario_id from {{ source('epm_gold', 'scenario_definitions') }}
)
