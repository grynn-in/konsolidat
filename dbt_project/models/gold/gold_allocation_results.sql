{{
    config(
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# PRD-3: Multi-step cascading allocations #}
{{ allocation_engine_multistep() }}
