-- Allocation dimension is declared (konsol#269, T3). A run's allocation_dimension
-- must be one of the site's In Budget dimensions, compiled from
-- get_budget_dimensions(). A site with none declares none, so every run flags.
select name as run, allocation_dimension
from {{ source('epm_staging', 'cost_allocation_runs') }}
where not has(
    cast([{% for d in get_budget_dimensions() %}'{{ d.name }}'{% if not loop.last %}, {% endif %}{% endfor %}] as Array(String)),
    allocation_dimension
)
