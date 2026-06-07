{{
    config(
        engine='MergeTree()',
        order_by='(fiscal_period)'
    )
}}

{# Period dimension: maps fiscal_period to quarter, half, and period label.
   Uses configurable quarter/half mappings from dbt_project.yml vars.
   Extra periods (0=opening, 13=closing, etc.) are configured via fiscal_extra_periods var. #}

{% set q_map = var('fiscal_quarter_mapping', {1:'Q1',2:'Q1',3:'Q1',4:'Q2',5:'Q2',6:'Q2',7:'Q3',8:'Q3',9:'Q3',10:'Q4',11:'Q4',12:'Q4'}) %}
{% set h_map = var('fiscal_half_mapping', {1:'H1',2:'H1',3:'H1',4:'H1',5:'H1',6:'H1',7:'H2',8:'H2',9:'H2',10:'H2',11:'H2',12:'H2'}) %}
{% set extra_periods = var('fiscal_extra_periods', []) %}

{# Build all periods: extra pre-periods + standard 1-12 + extra post-periods #}
{% set all_periods = [] %}
{% for ep in extra_periods if ep.period < 1 %}
    {% do all_periods.append({'p': ep.period, 'label': ep.label, 'quarter': ep.quarter, 'half': ep.half}) %}
{% endfor %}
{% for p in range(1, 13) %}
    {% do all_periods.append({'p': p, 'label': 'P' ~ '%02d' | format(p), 'quarter': q_map[p], 'half': h_map[p]}) %}
{% endfor %}
{% for ep in extra_periods if ep.period > 12 %}
    {% do all_periods.append({'p': ep.period, 'label': ep.label, 'quarter': ep.quarter, 'half': ep.half}) %}
{% endfor %}

{% for row in all_periods %}
select
    {{ cast_to_uint8(row.p) }} as fiscal_period,
    '{{ row.label }}' as period_label,
    '{{ row.quarter }}' as fiscal_quarter,
    '{{ row.half }}' as fiscal_half
{{ 'union all' if not loop.last }}
{% endfor %}
