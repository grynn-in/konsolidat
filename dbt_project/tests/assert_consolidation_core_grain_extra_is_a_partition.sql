-- konsol#348 S4 (W3): consolidation_core()'s grain_extra columns are a pure partition.
-- The consolidation core (macros/consolidation_core.sql) takes `grain_extra`, the key columns a
-- caller adds to the consolidation grain beyond (group, entity, period, account, partner,
-- dimensions): the budget model passes scenario_id, cycle and layer; the actuals model passes
-- none. Each value of such a column must be a consolidation of its own: the same rows run under
-- two layers must give, per layer, exactly the rows they give alone. If any one select, group by,
-- join or window partition inside the core lacks the extra grain, two layers of one key telescope
-- into each other without an error: the retranslation window sums both layers' balances, a filler
-- for one layer hides the other's row, the year-end close credits retained earnings with both
-- layers' results. The plan for S4 lists the windows at risk (key_before, key_all,
-- key_year_before, close_period) and the retranslated_keys group by.
-- This test runs the core twice on the partner trial balance: once as the actuals model does
-- (no extra grain), once on the same rows duplicated under zz_layer 'ZZA' and 'ZZB' with
-- grain_extra=['zz_layer']. The second must equal the first under each layer: a multiset diff
-- (UNION ALL + GROUP BY with +1/-1 signs; never count() over EXCEPT, konsolidat#361) names any
-- row that differs. Float columns are rounded to 6 places: `sum() over close_period` adds its
-- rows in pipeline order, so the last binary digit may differ between two runs; a telescoped
-- layer differs by the size of a balance.
-- The test calls the macro directly, so it needs no model of its own and the fixture
-- (test_fixtures/assert_consolidation_core_grain_extra_is_a_partition.sql) seeds the core's
-- inputs only: a retranslated balance, a year-end close and a historical tranche.
-- Flagged rows: the key, the layer, and net = +1 (expected under the layer, not produced) or
-- -1 (produced, not expected).
{%- set lead = ['consolidation_group', 'data_area_id', 'fiscal_year', 'fiscal_period', 'main_account',
                'account_name', 'account_type_name', 'is_balance_sheet', 'is_pnl', 'is_equity',
                'partner_data_area_id'] -%}
{%- set dimension_names = [] -%}
{%- for d in get_dimensions() %}{% do dimension_names.append(d.name) %}{% endfor -%}
{%- set exact_tail = ['local_amount', 'accounting_currency', 'reporting_currency', 'consolidation_method',
                      'uses_historical_rate', 'fx_method', 'is_retained_earnings', 'is_year_end_close',
                      'is_filler'] -%}
{%- set rounded = ['ownership_pct', 'closing_rate', 'average_rate', 'historical_equity_rate',
                   'translation_rate', 'translation_adjustment', 'translated_amount', 'group_amount',
                   'nci_amount'] -%}
{%- set key = lead + dimension_names + ['zz_layer'] + exact_tail -%}
{#- r_<column>: a fresh alias, as an alias equal to a column name is a cyclic alias in ClickHouse -#}
{%- set rounded_exprs = [] -%}
{%- set rounded_names = [] -%}
{%- for c in rounded %}
    {%- do rounded_exprs.append('round(' ~ c ~ ', 6) as r_' ~ c) %}
    {%- do rounded_names.append('r_' ~ c) %}
{%- endfor -%}
{%- set projection = (key + rounded_exprs) | join(', ') -%}
{%- set grouping = (key + rounded_names) | join(', ') -%}

with base_source as (
    select
        data_area_id,
        fiscal_year,
        fiscal_period,
        main_account,
        account_name,
        account_type_name,
        is_balance_sheet,
        is_pnl,
        partner_data_area_id,
        {{ dim_select(trailing=true) }}
        period_debit - period_credit as local_amount,
        is_year_end_close
    from {{ ref('gold_trial_balance_by_partner') }}
),

{{ consolidation_core(source_cte='base_source', dims=get_dimensions(),
                      ownership_cte=ref('gold_entity_ownership'), grain_extra=[], scoped=false, p='base_') }},

{# the same rows under two layers: each layer must consolidate as the whole does #}
layered_source as (
    select s.*, zz_layer
    from base_source as s
    array join ['ZZA', 'ZZB'] as zz_layer
),

{{ consolidation_core(source_cte='layered_source', dims=get_dimensions(),
                      ownership_cte=ref('gold_entity_ownership'), grain_extra=['zz_layer'], scoped=false, p='layered_') }},

expected as (
    select c.*, zz_layer
    from base_consolidated as c
    array join ['ZZA', 'ZZB'] as zz_layer
),

diff as (
    select {{ grouping }}, sum(sign) as net
    from (
        select {{ projection }}, 1 as sign from expected
        union all
        select {{ projection }}, -1 as sign from layered_consolidated
    )
    group by {{ grouping }}
    having net != 0
)

select *
from diff
order by consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account, zz_layer, net
