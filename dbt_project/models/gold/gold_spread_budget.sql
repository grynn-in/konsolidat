{{
    config(
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# PRD-6: Budget spreading — takes annual inputs and spreads across 12 periods
   using normalized profile weights #}

with annual_input as (
    select
        scenario_id,
        data_area_id,
        {{ cast_to_uint16('fiscal_year') }} as fiscal_year,
        main_account,
        {{ dim_select(dims=get_budget_dimensions()) }},
        annual_amount,
        spread_profile_id,
        submitted_by
    from {{ ref('budget_annual_input') }}
),

{# Normalize profile weights so they sum to 1.0 per profile #}
profiles as (
    select
        profile_id,
        profile_name,
        {{ cast_to_uint8('fiscal_period') }} as fiscal_period,
        weight,
        weight / sum(weight) over (partition by profile_id) as period_weight
    from {{ ref('spread_profiles') }}
),

spread as (
    select
        ai.scenario_id as scenario_id,
        ai.data_area_id as data_area_id,
        ai.fiscal_year as fiscal_year,
        p.fiscal_period as fiscal_period,
        ai.main_account as main_account,
        {{ dim_select(prefix='ai.', dims=get_budget_dimensions()) }},
        ai.annual_amount as annual_amount,
        ai.spread_profile_id as spread_profile_id,
        p.profile_name as profile_name,
        p.period_weight as period_weight,
        ai.annual_amount * p.period_weight as period_amount,
        ai.submitted_by as submitted_by
    from annual_input as ai
    inner join profiles as p
        on ai.spread_profile_id = p.profile_id
)

select * from spread
