{# PRD-9: Resolve ownership percentage for a given group/entity/period
   Returns ownership_pct and consolidation_method from temporal staging,
   falling back to static consolidation_groups seed #}

{% macro resolve_period_ownership(group_col, entity_col, period_date_col) %}
    coalesce(
        (
            select op.ownership_pct
            from {{ source('epm_staging', 'ownership_periods') }} as op
            where op.consolidation_group = {{ group_col }}
              and op.data_area_id = {{ entity_col }}
              and {{ period_date_col }} >= op.effective_date
              and {{ period_date_col }} <= op.end_date
            order by op.effective_date desc
            limit 1
        ),
        (
            select cg.ownership_pct
            from {{ ref('consolidation_groups') }} as cg
            where cg.data_area_id = {{ entity_col }}
            limit 1
        )
    )
{% endmacro %}

{% macro resolve_period_method(group_col, entity_col, period_date_col) %}
    coalesce(
        (
            select op.consolidation_method
            from {{ source('epm_staging', 'ownership_periods') }} as op
            where op.consolidation_group = {{ group_col }}
              and op.data_area_id = {{ entity_col }}
              and {{ period_date_col }} >= op.effective_date
              and {{ period_date_col }} <= op.end_date
            order by op.effective_date desc
            limit 1
        ),
        (
            select cg.consolidation_method
            from {{ ref('consolidation_groups') }} as cg
            where cg.data_area_id = {{ entity_col }}
            limit 1
        )
    )
{% endmacro %}
