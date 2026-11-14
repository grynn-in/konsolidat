-- Test: each ANNUAL-spread budget line spreads into every declared Regular period of its
-- fiscal year (epm_staging.fiscal_periods, period_type = 'Regular') and into no other period.
-- A site's year is not always 12 periods (a 13-period 4-4-5 or 4-weekly calendar), so the count
-- comes from the declared calendar, not from a constant (konsolidat Q12-b; replaces the
-- hard-coded 12 of assert_spread_has_12_periods, konsolidat#94).
-- Flags one row per line: periods_missing counts declared Regular periods the profile skips,
-- periods_outside counts spread periods that are not declared Regular (a Closing period, or a
-- year with no declared calendar).
-- Excludes manual (identity-spread) budgets (#94): a manually-entered budget can
-- legitimately be partial-year, so it carries no structural period guarantee.
-- join_use_nulls=0: the comparisons use NOT IN, never a LEFT JOIN.
with declared as (
    select fiscal_year, fiscal_period
    from {{ source('epm_staging', 'fiscal_periods') }}
    where period_type = 'Regular'
),

spread as (
    select scenario_id, data_area_id, fiscal_year, main_account, spread_profile_id, fiscal_period
    from {{ ref('gold_spread_budget') }}
    where spread_profile_id != 'manual'
),

line as (
    select distinct scenario_id, data_area_id, fiscal_year, main_account, spread_profile_id
    from spread
),

missing as (
    select
        l.scenario_id as scenario_id,
        l.data_area_id as data_area_id,
        l.fiscal_year as fiscal_year,
        l.main_account as main_account,
        l.spread_profile_id as spread_profile_id,
        1 as periods_missing,
        0 as periods_outside
    from line as l
    inner join declared as d on l.fiscal_year = d.fiscal_year
    where (l.scenario_id, l.data_area_id, l.fiscal_year, l.main_account, l.spread_profile_id, d.fiscal_period) not in (
        select scenario_id, data_area_id, fiscal_year, main_account, spread_profile_id, fiscal_period
        from spread
    )
),

outside as (
    select
        scenario_id, data_area_id, fiscal_year, main_account, spread_profile_id,
        0 as periods_missing,
        1 as periods_outside
    from spread
    where (fiscal_year, fiscal_period) not in (select fiscal_year, fiscal_period from declared)
)

select
    scenario_id,
    data_area_id,
    fiscal_year,
    main_account,
    spread_profile_id,
    sum(periods_missing) as periods_missing,
    sum(periods_outside) as periods_outside
from (select * from missing union all select * from outside)
group by scenario_id, data_area_id, fiscal_year, main_account, spread_profile_id
