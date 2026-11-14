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
     (b) manually-entered monthly budgets (epm_raw.budget_entries, konsol's
         Budget Entry lines; konsol#348 S2), treated as an "identity" spread —
         the entered monthly values ARE the weights (profile_id = 'manual').

   Budget LAYERS (base / challenge / management / board): the final budget is the
   sum of all layers. All layers are carried here as separate rows with a `layer`
   column; K.EPM sums them by default (no layer filter) and filters to one when a
   layer is passed (Dataset.has_layer). Each Annual Input declares its own layer
   (R6), and the annual branch carries it.

   One writer per grain (konsol#348 Q16-c, 13 Nov 2026, Deepak Pai's standing
   rule): konsol refuses an Annual Input and a manual Budget Entry line on one
   (scenario, entity, year, layer, account, budget dims). The two branches are
   therefore a plain UNION ALL with no precedence rule;
   assert_budget_one_writer_per_grain is the backstop that names any overlap. #}

with annual_input as (
    select
        scenario_id,
        data_area_id,
        {{ cast_to_uint16('fiscal_year') }} as fiscal_year,
        main_account,
        {{ dim_select(dims=get_budget_dimensions(), trailing=true) }}
        layer,
        annual_amount,
        spread_profile_id,
        submitted_by
    {# konsolidat#146: konsol's Budget Annual Input doctype, not a seed in this
       repo. The other branch of this model reads konsol's
       epm_raw.budget_entries, so both halves of budget input are the app's. #}
    from {{ source('epm_gold', 'budget_annual_input') }}
),

{# Normalize profile weights so they sum to 1.0 per profile #}
profiles as (
    select
        profile_id,
        profile_name,
        {{ cast_to_uint8('fiscal_period') }} as fiscal_period,
        weight,
        weight / sum(weight) over (partition by profile_id) as period_weight
    {# konsolidat#146: the seed behind this ref materialised into
       epm_gold.spread_profiles — the same relation konsol's Spread Profile
       doctype TRUNCATE+INSERTs, so whichever of `dbt seed` and `bench migrate`
       ran last won. The doctype is the source. #}
    from {{ source('epm_gold', 'spread_profiles') }}
),

{# (b) Manually-entered monthly budgets as an identity spread (konsol#348 S2,
   R2). Each epm_raw.budget_entries line is a debit or a credit; the fact carries
   net = debit - credit, debit positive, signed like actuals (BUD-7), summed to
   one value per (scenario, entity, year, period, account, budget dims, layer):
   several lines on one grain are one fact row.
   The fact holds period MOVEMENTS (Q15-c, R10). A 'Period movement' line is
   one as landed. A 'Year-to-date movement' line is converted within the Cycle
   year by the rule silver_tb_movements uses for actuals, written once in
   macros/period_movements.sql: movement(p) = YTD(p) - YTD(previous period),
   the first period of the year is its YTD, and a key missing in a later period
   reads YTD 0, so its movement reverses the previous YTD. The series is
   (cycle, scenario, layer, entity, account, budget dims): a layer is never
   differenced against another, nor against actuals. A 'Period-end balance'
   line is NOT read: it needs an opening balance, which is an open policy
   question. assert_budget_basis_supported names every such line, and every
   (cycle, entity, layer, year) that mixes bases, so none is dropped or
   combined silently. Keep the literals below identical to that test's.
   ALL layers are carried (challenge/management/board as well as base); the
   per-layer monthly values normalize within their own layer (window partitions
   on layer too). annual_amount / period_weight are derived from the monthly
   values so the row shape matches the annual-spread branch. #}
{%- set budget_dim_names = get_budget_dimensions() | map(attribute='name') | list -%}
{%- set ytd_scope = ['cycle', 'scenario_id', 'layer', 'data_area_id'] -%}
{%- set ytd_key_columns = ['main_account'] + budget_dim_names %}
ytd_lines as (
    {# the stated year-to-date figure per key and period #}
    select
        cycle,
        scenario_id,
        layer,
        data_area_id,
        fiscal_year,
        fiscal_period,
        main_account,
        {{ dim_select(dims=get_budget_dimensions(), trailing=true) }}
        sum(debit - credit) as source_net_amount,
        toUInt8(1) as has_source
    from {{ source('budget_raw', 'budget_entries') }}
    where amount_basis = 'Year-to-date movement'
    group by
        cycle,
        scenario_id,
        layer,
        data_area_id,
        fiscal_year,
        fiscal_period,
        main_account
        {{- dim_group_by(dims=get_budget_dimensions(), leading=true) }}
),

{# the periods a (cycle, scenario, layer, entity) states a YTD figure for: the
   budget's analogue of an entity's claimed TB periods #}
ytd_periods as (
    select distinct cycle, scenario_id, layer, data_area_id, fiscal_year, fiscal_period
    from ytd_lines
),

ytd_keys as (
    select distinct
        cycle, scenario_id, layer, data_area_id, main_account
        {{- dim_select(dims=get_budget_dimensions(), leading=true) }}
    from ytd_lines
),

ytd_spine as (
    {{ movement_spine('ytd_periods', 'ytd_keys', 'ytd_lines', scope=ytd_scope, key_columns=ytd_key_columns) }}
),

ytd_movements as (
    select
        *,
        {{ ytd_movement(ytd_scope + ytd_key_columns) }} as net_amount
    from ytd_spine
),

manual_lines as (
    select
        scenario_id,
        data_area_id,
        fiscal_year,
        fiscal_period,
        main_account,
        {{ dim_select(dims=get_budget_dimensions(), trailing=true) }}
        layer,
        sum(net_amount) as net_amount
    from (
        select
            scenario_id,
            data_area_id,
            fiscal_year,
            fiscal_period,
            main_account,
            {{ dim_select(dims=get_budget_dimensions(), trailing=true) }}
            layer,
            toDecimal128(debit - credit, {{ amount_scale() }}) as net_amount
        from {{ source('budget_raw', 'budget_entries') }}
        where amount_basis = 'Period movement'

        union all

        {# a spine row that differences to 0 and has no stated figure is dropped,
           as in silver_tb_movements #}
        select
            scenario_id,
            data_area_id,
            fiscal_year,
            fiscal_period,
            main_account,
            {{ dim_select(dims=get_budget_dimensions(), trailing=true) }}
            layer,
            net_amount
        from ytd_movements
        where not (net_amount = 0 and has_source = 0)
    )
    group by
        scenario_id,
        data_area_id,
        fiscal_year,
        fiscal_period,
        main_account,
        {{ dim_group_by(dims=get_budget_dimensions(), trailing=true) }}
        layer
),

manual as (
    select
        scenario_id,
        data_area_id,
        {{ cast_to_uint16('fiscal_year') }} as fiscal_year,
        {{ cast_to_uint8('fiscal_period') }} as fiscal_period,
        main_account,
        {{ dim_select(dims=get_budget_dimensions(), trailing=true) }}
        layer,
        toFloat64(sum(net_amount) over w) as annual_amount,
        'manual' as spread_profile_id,
        'Manual (as-entered)' as profile_name,
        toFloat64(net_amount) / nullIf(toFloat64(sum(net_amount) over w), 0) as period_weight,
        toFloat64(net_amount) as period_amount,
        '' as submitted_by
    from manual_lines
    window w as (
        partition by scenario_id, data_area_id, fiscal_year, main_account,
                     {{ dim_group_by(dims=get_budget_dimensions(), trailing=true) }} layer
    )
),

{# (a) Annual inputs spread by profile. No manual row displaces an annual one
   (Q16-c): intake keeps the two writers on disjoint grains. #}
spread as (
    select
        ai.scenario_id as scenario_id,
        ai.data_area_id as data_area_id,
        ai.fiscal_year as fiscal_year,
        p.fiscal_period as fiscal_period,
        toString(ai.main_account) as main_account,
        {{ dim_select(prefix='ai.', dims=get_budget_dimensions(), trailing=true) }}
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
)

select * from spread
union all
select * from manual
