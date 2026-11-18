-- konsol#348 S4 (W4): every budget period an entity line-consolidates in is in the consolidated
-- budget. gold_consolidated_budget_tb resolves ownership on the BUDGET's own period spine
-- (budget_consolidation_inputs(), macros/budget_rates.sql, through ownership_resolution_ctes()),
-- not on gold_entity_ownership, whose spine is the periods the ACTUALS have rows in. A budget is
-- entered before its year starts, so most budget periods have no trial balance row; joined to the
-- actuals' ownership they had no ownership and vanished from the consolidation without an error.
-- This test rebuilds the expected keys the same way the model does and names every one the model
-- lacks: (group, scenario, cycle, layer, entity, year, period) for every fact row of an APPROVED
-- Cycle (epm_staging.budget_cycles) whose entity has a currency and, at that period, a complete
-- ownership chain into the group with method full or proportional. The core keeps every source row
-- that survives the ownership join (a missing rate stops the build rather than dropping a row), so
-- an expected key with no row in the model is a row the consolidation lost.
-- NOT IN rather than a LEFT JOIN null test (join_use_nulls=0).
{{ config(severity='error') }}

with {{ budget_consolidation_inputs(p='t_') }},

{{ ownership_resolution_ctes('t_budget_periods', 't_own_') }},

expected as (
    select distinct
        eo.consolidation_group as consolidation_group,
        f.scenario_id as scenario_id,
        f.cycle as cycle,
        f.layer as layer,
        f.data_area_id as data_area_id,
        f.fiscal_year as fiscal_year,
        f.fiscal_period as fiscal_period
    from t_budget_fact as f
    inner join (
        select data_area_id
        from {{ ref('silver_entity_currencies') }}
        where accounting_currency != ''
    ) as ec
        on ec.data_area_id = f.data_area_id
    inner join t_own_resolution as eo
        on eo.data_area_id = f.data_area_id
        and eo.fiscal_year = f.fiscal_year
        and eo.fiscal_period = f.fiscal_period
    where eo.consolidation_method not in ('equity', 'none')
      and eo.has_complete_chain = 1
),

built as (
    select distinct
        consolidation_group,
        scenario_id,
        cycle,
        layer,
        data_area_id,
        toUInt16(fiscal_year) as fiscal_year,
        toUInt16(fiscal_period) as fiscal_period
    from {{ ref('gold_consolidated_budget_tb') }}
)

select *
from expected
where (consolidation_group, scenario_id, cycle, layer, data_area_id, fiscal_year, fiscal_period) not in (
    select consolidation_group, scenario_id, cycle, layer, data_area_id, fiscal_year, fiscal_period
    from built
)
order by consolidation_group, scenario_id, cycle, layer, data_area_id, fiscal_year, fiscal_period
