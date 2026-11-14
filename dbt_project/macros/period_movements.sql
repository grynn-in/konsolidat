{# ============================================================
   Period movements from stated figures: the spine and the
   year-to-date rule, written once (konsol#348 S2, Q15-c, R10).

   silver_tb_movements (actuals) and gold_spread_budget (budget
   lines on 'Year-to-date movement') both call these, so the YTD
   rule cannot differ between the two. What differs is the SERIES:
   the columns a figure is differenced within. Actuals pass
   (data_area_id, main_account, partner_data_area_id, <dims>);
   budget passes (cycle, scenario_id, layer, data_area_id,
   main_account, <in_budget dims>), so a budget series is never
   differenced against actuals or against another layer.
   ============================================================ #}

{# movement_spine: periods x keys, a key with no source row reading 0.

   A YTD or balance file lists only its non-zero keys, so a key present in an
   earlier period and absent later has net 0 there, and its movement is minus
   the previous figure. Differencing only the rows that exist would miss that.
   So the spine crosses every period of a scope with every key of that scope
   and LEFT JOINs the stated figures; ClickHouse fills an unmatched LEFT JOIN
   side with the column defaults (join_use_nulls=0), so a missing key has
   source_net_amount 0 and has_source 0.

   periods   relation (CTE name) with <scope>, fiscal_year, fiscal_period and
             the period_columns
   keys      relation with <scope> and the key_columns
   source    relation with <scope>, fiscal_year, fiscal_period, the key_columns,
             the source_columns, source_net_amount and has_source (1 on every row)
   scope     columns the periods and the keys are matched on (actuals: the
             entity; budget: cycle, scenario, layer, entity)
   key_columns     columns that, with the scope, name one series
   period_columns  extra columns taken from the period row
   source_columns  extra columns taken from the source row

   Output columns, in this order: scope, fiscal_year, fiscal_period,
   key_columns, period_columns, source_columns, source_net_amount, has_source.
   The key values come from the KEY, never the source row, so an unmatched
   period still belongs to the same series. #}
{% macro movement_spine(periods, keys, source, scope, key_columns, period_columns=[], source_columns=[]) -%}
    select
        {% for c in scope -%}
        p.{{ c }} as {{ c }},
        {% endfor -%}
        p.fiscal_year as fiscal_year,
        p.fiscal_period as fiscal_period,
        {% for c in key_columns -%}
        k.{{ c }} as {{ c }},
        {% endfor -%}
        {% for c in period_columns -%}
        p.{{ c }} as {{ c }},
        {% endfor -%}
        {% for c in source_columns -%}
        s.{{ c }} as {{ c }},
        {% endfor -%}
        s.source_net_amount as source_net_amount,
        s.has_source as has_source
    from {{ periods }} as p
    inner join {{ keys }} as k
        on {% for c in scope %}{{ 'and ' if not loop.first }}p.{{ c }} = k.{{ c }}{{ ' ' if not loop.last }}{% endfor %}
    left join {{ source }} as s
        on {% for c in scope %}s.{{ c }} = p.{{ c }} and {% endfor %}s.fiscal_year = p.fiscal_year
        and s.fiscal_period = p.fiscal_period
        {%- for c in key_columns %}
        and s.{{ c }} = k.{{ c }}
        {%- endfor %}
{%- endmacro %}

{# ytd_movement: the 'Year-to-date movement' rule, as one expression.

   movement(p) = value(p) - value(previous period of the SAME series in the SAME
   fiscal year); the first period of a year has no previous one and its
   movement is value(p). Periods are ordered by fiscal_period among the rows
   the spine holds, so run it over movement_spine's output: a vanished key then
   has its 0 row and its YTD is reversed.

   series  the columns that name one series (fiscal_year is added here)
   value   the stated year-to-date figure #}
{% macro ytd_movement(series, value='source_net_amount') -%}
    {{ value }} - lagInFrame({{ value }}, 1, toDecimal128(0, {{ amount_scale() }})) over (
        partition by {{ series | join(', ') }}, fiscal_year
        order by fiscal_period
        rows between unbounded preceding and current row
    )
{%- endmacro %}
