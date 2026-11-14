{#
    Budget year-to-date lines reconcile to the spread (konsol#348 S2, Q15-c, R10).

    gold_spread_budget converts every epm_raw.budget_entries line on
    'Year-to-date movement' into period movements within the Cycle year. Undoing
    that conversion must give the stated figure back: for every key a (cycle,
    scenario, layer, entity) states in that year, and every period it states any
    YTD figure for, the running sum of the spread's manual movements through that
    period equals the stated YTD. A key missing from a period's lines has a
    stated YTD of 0 there (the spine of macros/period_movements.sql), so a key
    that vanishes must have been reversed: a model that only differenced the
    rows that exist leaves its last YTD standing and is named here.

    The spread has no cycle column, so the stated figures are summed to the
    spread's grain (scenario, entity, year, period, account, budget dims,
    layer). A grain that mixes bases in one year does not reconcile either;
    assert_budget_basis_supported names that case by itself.

    Flags one row per (grain, period) that does not reconcile. Tolerance 0.01,
    as for the TB balance tests.
#}

{{ config(severity='error') }}

{%- set budget_dim_names = get_budget_dimensions() | map(attribute='name') | list -%}
{%- set ytd_scope = ['cycle', 'scenario_id', 'layer', 'data_area_id'] -%}
{%- set ytd_key_columns = ['main_account'] + budget_dim_names %}

with ytd_lines as (
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

{# the stated YTD on every (key, period) of the spine, 0 where the key is absent #}
stated as (
    {{ movement_spine('ytd_periods', 'ytd_keys', 'ytd_lines', scope=ytd_scope, key_columns=ytd_key_columns) }}
),

{# UNION + GROUP BY, not a LEFT JOIN: join_use_nulls=0 would fill an unmatched
   side with 0 and hide a missing spread row #}
combined as (
    select
        scenario_id, layer, data_area_id,
        toUInt16(fiscal_year) as fiscal_year,
        toUInt8(fiscal_period) as fiscal_period,
        toString(main_account) as main_account,
        {{ dim_select(dims=get_budget_dimensions(), trailing=true) }}
        toFloat64(source_net_amount) as stated_ytd,
        toFloat64(0) as movement,
        toUInt8(1) as on_spine
    from stated

    union all

    select
        scenario_id, layer, data_area_id,
        toUInt16(fiscal_year) as fiscal_year,
        toUInt8(fiscal_period) as fiscal_period,
        toString(main_account) as main_account,
        {{ dim_select(dims=get_budget_dimensions(), trailing=true) }}
        toFloat64(0) as stated_ytd,
        toFloat64(period_amount) as movement,
        toUInt8(0) as on_spine
    from {{ ref('gold_spread_budget') }}
    where spread_profile_id = 'manual'
),

per_period as (
    select
        scenario_id, layer, data_area_id, fiscal_year, fiscal_period, main_account,
        {{ dim_select(dims=get_budget_dimensions(), trailing=true) }}
        sum(stated_ytd) as stated_ytd,
        sum(movement) as movement,
        max(on_spine) as on_spine
    from combined
    group by
        scenario_id, layer, data_area_id, fiscal_year, fiscal_period, main_account
        {{- dim_group_by(dims=get_budget_dimensions(), leading=true) }}
),

cumulated as (
    select
        *,
        sum(movement) over (
            partition by scenario_id, layer, data_area_id, fiscal_year, main_account
                {{- dim_partition_by(dims=get_budget_dimensions(), leading=true) }}
            order by fiscal_period
            rows between unbounded preceding and current row
        ) as cumulative_movement
    from per_period
)

select
    scenario_id,
    layer,
    data_area_id,
    fiscal_year,
    fiscal_period,
    main_account,
    {{ dim_select(dims=get_budget_dimensions(), trailing=true) }}
    stated_ytd,
    cumulative_movement
from cumulated
where on_spine = 1
  and abs(stated_ytd - cumulative_movement) > 0.01
