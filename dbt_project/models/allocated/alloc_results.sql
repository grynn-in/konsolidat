{{
    config(
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# PRD-ALLOCATED-LAYER PR1: allocation output in epm_allocated (scenario-aware) #}
select
    'ACTUAL' as scenario_id,
    engine.*
from (
    {{ allocation_engine_multistep() }}
) as engine