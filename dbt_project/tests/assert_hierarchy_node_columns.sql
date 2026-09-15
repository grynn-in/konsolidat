{# konsolidat#206: the hierarchy node models name their dimension column
   hierarchy_dimension. Each selects it from the leaf closure (lc) in a join
   whose other side (the long form of the TB / variance / budget) has a
   hierarchy_dimension column too; unaliased, ClickHouse keeps the qualifier
   and the column comes out as `lc.hierarchy_dimension`, which no reader can
   select by its plain name. One row per model with no column named
   hierarchy_dimension. #}

{% set node_models = ['gold_variance_at_hierarchy_node', 'gold_tb_at_hierarchy_node', 'gold_budget_at_hierarchy_node'] %}
{# the refs below sit behind `execute`, so declare them for the DAG #}
-- depends_on: {{ ref('gold_variance_at_hierarchy_node') }}
-- depends_on: {{ ref('gold_tb_at_hierarchy_node') }}
-- depends_on: {{ ref('gold_budget_at_hierarchy_node') }}

{% set missing = [] %}
{% if execute %}
    {% for m in node_models %}
        {% set cols = adapter.get_columns_in_relation(ref(m)) | map(attribute='name') | list %}
        {% if 'hierarchy_dimension' not in cols %}
            {% do missing.append(m) %}
        {% endif %}
    {% endfor %}
{% endif %}

{% if missing %}
    {% for m in missing %}
select '{{ m }}' as model_name
        {% if not loop.last %}union all{% endif %}
    {% endfor %}
{% else %}
select '' as model_name where 0
{% endif %}
