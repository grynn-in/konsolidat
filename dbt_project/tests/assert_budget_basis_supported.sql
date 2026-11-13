-- Test: every epm_raw.budget_entries line has an amount_basis that gold_spread_budget reads.
-- Today it reads 'Period movement' only (R2 sums those as movements). A line on any other basis
-- ('Year-to-date movement', 'Period-end balance') would be dropped from the budget fact without a
-- trace; this test names each one, so the drop is visible. Keep the literal below identical to the
-- filter in gold_spread_budget.sql.
-- Temporary (konsol#348 Q15-c): replaced or narrowed when R10 lands and converts the other bases.
-- Flags one row per unread line.
select
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
where amount_basis != 'Period movement'
