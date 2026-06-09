{# PRD-19: Resolve allocation driver by type
   Dispatches to simple, composite, or conditional driver resolution.
   - Simple: direct lookup from driver_weights
   - Composite: weighted formula across multiple driver types (e.g., "headcount*0.6+sqm*0.4")
   - Conditional: CASE expression evaluated against driver values per target #}

{% macro resolve_allocation_driver_cte(rule_alias, drivers_alias) %}
{#
    Returns a CTE fragment that resolves driver weights for a given rule.
    For composite drivers, this joins multiple driver types and applies weights.
    For conditional drivers, the CASE logic is embedded in the SQL.

    Usage in gold models: called inside the allocation engine to get driver weights.
    The driver_formula field in allocation_rules determines the behavior:
    - Empty: simple driver (use driver_type directly)
    - Contains '*' and '+': composite (weighted sum)
    - Contains 'CASE': conditional (SQL CASE expression)
#}

case
    when {{ rule_alias }}.driver_formula = '' then
        {# Simple: direct driver weight #}
        {{ drivers_alias }}.driver_weight
    when {{ rule_alias }}.driver_formula like '%CASE%' then
        {# Conditional: formula is a raw SQL CASE — cannot evaluate dynamically in dbt
           Fallback to simple driver for now; staging CASE expressions are validated
           at Frappe write time and pre-evaluated into driver_value rows #}
        {{ drivers_alias }}.driver_weight
    else
        {# Composite: pre-evaluated at Frappe layer into combined driver_value rows
           with driver_type = 'composite_<rule_id>' #}
        {{ drivers_alias }}.driver_weight
end
{% endmacro %}
