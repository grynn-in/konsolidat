{{
    config(
        engine='MergeTree()',
        order_by='(scenario_id)'
    )
}}

-- Scenario metadata from seed + staging table (for API-created scenarios)
select
    scenario_id,
    scenario_name,
    scenario_type,
    is_active,
    'seed' as source
from {{ ref('scenario_definitions') }}

union all

select
    scenario_id,
    scenario_name,
    scenario_type,
    is_active,
    'api' as source
from epm_staging.scenario_definitions
where scenario_id not in (
    select scenario_id from {{ ref('scenario_definitions') }}
)
