{{
    config(
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# PRD-6 / grynn-in/konsolidat#94: canonical monthly budget fact — one row per
   (scenario, entity, fiscal_year, fiscal_period, main_account, budget dims, layer).
   UNION of the two budget entry methods so both land in the SAME place and are
   read identically by K.EPM's `budget_input` fact and gold_scenario_trial_balance:

     (a) annual inputs spread across 12 periods by a profile (PRD-6); and
     (b) manually-entered monthly budgets (epm_gold.budget_monthly_input),
         treated as an "identity" spread — the typed monthly values ARE the
         weights (profile_id = 'manual').

   Budget LAYERS (base / challenge / management / board): the final budget is the
   sum of all layers. All layers are carried here as separate rows with a `layer`
   column; K.EPM sums them by default (no layer filter) and filters to one when a
   layer is passed (Dataset.has_layer). Annual-spread inputs have no layer of
   their own (the seed predates layering) and are treated as the 'base' layer. #}

with annual_input as (
    select
        scenario_id,
        data_area_id,
        {{ cast_to_uint16('fiscal_year') }} as fiscal_year,
        main_account,
        {{ dim_select(dims=get_budget_dimensions()) }},
        'base' as layer,
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

{# (b) Manually-entered monthly budgets as an identity spread. ALL layers are
   carried (challenge/management/board as well as base); the per-layer monthly
   values normalize within their own layer (window partitions on layer too).
   annual_amount / period_weight are derived from the monthly values so the row
   shape matches the annual-spread branch. #}
manual as (
    select
        scenario_id,
        data_area_id,
        {{ cast_to_uint16('fiscal_year') }} as fiscal_year,
        {{ cast_to_uint8('fiscal_period') }} as fiscal_period,
        main_account,
        {{ dim_select(dims=get_budget_dimensions()) }},
        layer,
        toFloat64(sum(amount) over w) as annual_amount,
        'manual' as spread_profile_id,
        'Manual (as-entered)' as profile_name,
        toFloat64(amount) / nullIf(toFloat64(sum(amount) over w), 0) as period_weight,
        toFloat64(amount) as period_amount,
        '' as submitted_by
    from {{ source('epm_gold', 'budget_monthly_input') }}
    window w as (
        partition by scenario_id, data_area_id, fiscal_year, main_account,
                     {{ dim_group_by(dims=get_budget_dimensions()) }}, layer
    )
),

{# Precedence: a manual monthly budget OVERRIDES an annual-spread one for the
   same (scenario, entity, year, account, dims) grain — explicit per-month values
   win and we never double-count. Annual inputs are the 'base' layer, so only a
   manual BASE row displaces them; non-base manual layers are purely additive.
   Disjoint grains keep both branches. #}
spread as (
    select
        ai.scenario_id as scenario_id,
        ai.data_area_id as data_area_id,
        ai.fiscal_year as fiscal_year,
        p.fiscal_period as fiscal_period,
        toString(ai.main_account) as main_account,
        {{ dim_select(prefix='ai.', dims=get_budget_dimensions()) }},
        ai.layer as layer,
        toFloat64(ai.annual_amount) as annual_amount,
        ai.spread_profile_id as spread_profile_id,
        p.profile_name as profile_name,
        p.period_weight as period_weight,
        toFloat64(ai.annual_amount) * p.period_weight as period_amount,
        ai.submitted_by as submitted_by
    from annual_input as ai
    inner join profiles as p
        on ai.spread_profile_id = p.profile_id
    where (
        ai.scenario_id, ai.data_area_id, ai.fiscal_year, toString(ai.main_account),
        {{ dim_group_by(prefix='ai.', dims=get_budget_dimensions()) }}
    ) not in (
        select
            scenario_id, data_area_id, fiscal_year, main_account,
            {{ dim_group_by(dims=get_budget_dimensions()) }}
        from manual
        where layer = 'base'
    )
)

select * from spread
union all
select * from manual
