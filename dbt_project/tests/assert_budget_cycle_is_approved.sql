-- konsol#348 S4 (W4, S4-Q2 a; premise reworded after the #368 review): a sync-drift check between
-- the three budget write-throughs. Since S3, Budget Annual Input rows (epm_gold.budget_annual_input)
-- and Budget Entry lines (epm_raw.budget_entries) reach ClickHouse only while their Cycle is
-- approved, and the approved Cycle itself reaches epm_staging.budget_cycles with its Rate Set. So
-- in a consistent warehouse every Cycle gold_spread_budget names has a budget_cycles row, and
-- gold_consolidated_budget_tb (which joins the fact to budget_cycles on the Cycle's name) consolidates
-- every fact row. A row here is drift between the three write-throughs, not a draft budget: a
-- Cycle cancelled or deleted after its lines synced, a reconcile_all that repaired one table and not
-- another, a load that seeded the fact without the Cycle. The fact rows of such a Cycle are silently
-- not translated, so this names every (scenario, cycle) the fact holds and budget_cycles does not,
-- with the row count and years, for konsol.clickhouse.reconcile_all() to repair. Warn, not error:
-- the missing Cycle's rows are the only ones affected, and the rest of the budget must still build.
-- NOT IN rather than a LEFT JOIN null test (join_use_nulls=0).
{{ config(severity='warn') }}

select
    scenario_id,
    cycle,
    count() as fact_rows,
    min(fiscal_year) as first_year,
    max(fiscal_year) as last_year
from {{ ref('gold_spread_budget') }}
where cycle not in (select name from {{ source('epm_staging', 'budget_cycles') }})
group by scenario_id, cycle
order by scenario_id, cycle
