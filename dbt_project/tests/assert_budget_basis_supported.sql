-- Test: every epm_raw.budget_entries line is on a basis gold_spread_budget reads, and no
-- (cycle, entity, layer, year) mixes bases (konsol#348 S2, R9; narrowed by R10 under Q15-c).
--
-- gold_spread_budget reads two bases: 'Period movement' lines as landed, and 'Year-to-date movement'
-- lines converted to movements within the Cycle year (macros/period_movements.sql). Keep the two
-- literals below identical to the filters there.
--   * A 'Period-end balance' line is not read: converting it needs an opening balance, which is an
--     open policy question (Q15-c). Each such line is named, so none is dropped silently. So is a line
--     on any other string, which the spread would drop the same way.
--   * A (cycle, entity, layer, year) that holds more than one basis is named once: a YTD figure cannot
--     be differenced against a movement, and the spread would sum the two shapes as one.
-- Error severity: the budget fact would be wrong or incomplete.
{{ config(severity='error') }}

select
    'basis not read' as problem,
    entry_name,
    cycle,
    scenario_id,
    layer,
    data_area_id,
    fiscal_year,
    fiscal_period,
    main_account,
    amount_basis
from {{ source('budget_raw', 'budget_entries') }}
where amount_basis not in ('Period movement', 'Year-to-date movement')

union all

{# the bases are aggregated under their own alias, then renamed outside: an alias equal to the
   amount_basis column read by the sibling aggregates is refused (ILLEGAL_AGGREGATION) #}
select
    'more than one basis' as problem,
    '' as entry_name,
    cycle,
    scenario_id,
    layer,
    data_area_id,
    fiscal_year,
    toUInt8(0) as fiscal_period,
    '' as main_account,
    bases as amount_basis
from (
    select
        cycle,
        any(scenario_id) as scenario_id,
        layer,
        data_area_id,
        fiscal_year,
        arrayStringConcat(arraySort(groupUniqArray(amount_basis)), ', ') as bases
    from {{ source('budget_raw', 'budget_entries') }}
    group by cycle, data_area_id, layer, fiscal_year
    having uniqExact(amount_basis) > 1
)
