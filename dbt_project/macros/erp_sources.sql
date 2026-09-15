{# ============================================================
   ERP source switch (konsolidat#207)

   The canonical staging models UNION one adapter per ERP listed in the
   `erp_sources` var. A site whose only source is the trial-balance upload
   lists none. Each canonical model then compiles to `empty_relation(...)`:
   no rows, and the same column names and types it emits with an adapter.
   The models downstream keep building, and never see invalid SQL.

   columns: a list of (name, ClickHouse type) pairs, in output order, e.g.
       empty_relation([('erp_source', 'String'), ('amount', 'Nullable(Decimal(38, 9))')])
   Each column is the type's default value (defaultValueOfTypeName), so its
   type is exact. `where 0` keeps the relation empty.
   ============================================================ #}

{% macro empty_relation(columns) %}
select
    {%- for col in columns %}
    defaultValueOfTypeName('{{ col[1] }}') as {{ col[0] }}{{ ',' if not loop.last }}
    {%- endfor %}
where 0
{% endmacro %}
