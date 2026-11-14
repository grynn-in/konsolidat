-- konsol#348 S2 (R8, Q16-c, decided 13 Nov 2026 under Deepak Pai's standing rule): a budget grain
-- (scenario, entity, year, layer, account, budget dims) has ONE writer. konsol's intake refuses an
-- Annual Input and a manual Budget Entry line on the same grain, so gold_spread_budget is a plain
-- UNION ALL of the two branches with no precedence rule. This test is the warehouse backstop: it
-- flags every grain fed by both, naming the annual side (spread profile, submitter) and the manual
-- side (Budget Entries and cycles). Any amount_basis counts: every manual line is a writer.
-- Flags one row per doubly-written grain.
{{ config(severity='error') }}

with annual as (
    select
        scenario_id,
        data_area_id,
        toUInt16(fiscal_year) as fiscal_year,
        layer,
        toString(main_account) as main_account,
        {{ dim_select(dims=get_budget_dimensions(), trailing=true) }}
        groupUniqArray(spread_profile_id) as annual_spread_profiles,
        groupUniqArray(submitted_by) as annual_submitted_by
    from {{ source('epm_gold', 'budget_annual_input') }}
    group by
        scenario_id,
        data_area_id,
        fiscal_year,
        layer,
        main_account
        {{- dim_group_by(dims=get_budget_dimensions(), leading=true) }}
),

manual as (
    select
        scenario_id,
        data_area_id,
        toUInt16(fiscal_year) as fiscal_year,
        layer,
        toString(main_account) as main_account,
        {{ dim_select(dims=get_budget_dimensions(), trailing=true) }}
        groupUniqArray(entry_name) as manual_entries,
        groupUniqArray(cycle) as manual_cycles
    from {{ source('budget_raw', 'budget_entries') }}
    group by
        scenario_id,
        data_area_id,
        fiscal_year,
        layer,
        main_account
        {{- dim_group_by(dims=get_budget_dimensions(), leading=true) }}
)

select
    a.scenario_id as scenario_id,
    a.data_area_id as data_area_id,
    a.fiscal_year as fiscal_year,
    a.layer as layer,
    a.main_account as main_account,
    {{ dim_select(prefix='a.', dims=get_budget_dimensions(), trailing=true) }}
    a.annual_spread_profiles as annual_spread_profiles,
    a.annual_submitted_by as annual_submitted_by,
    m.manual_entries as manual_entries,
    m.manual_cycles as manual_cycles
from annual as a
inner join manual as m
    on a.scenario_id = m.scenario_id
    and a.data_area_id = m.data_area_id
    and a.fiscal_year = m.fiscal_year
    and a.layer = m.layer
    and a.main_account = m.main_account
    {{ dim_join_on('a', 'm', dims=get_budget_dimensions()) }}
