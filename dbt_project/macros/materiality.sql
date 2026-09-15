{# The materiality floor (konsolidat#209): the half-cent below which an
   amount is treated as zero when posting or reconciling. One definition, so
   a later change (a group-declared floor, a currency-scaled floor) is one
   edit. In SQL write {{ materiality_floor() }}; inside a Jinja expression,
   materiality_floor(). tests/test_materiality_literal.py keeps the literal
   out of every other model, macro and test. #}
{% macro materiality_floor() %}0.005{% endmacro %}
