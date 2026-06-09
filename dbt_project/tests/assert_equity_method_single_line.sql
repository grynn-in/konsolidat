-- PRD-14 Test: Equity method entities must appear as single-line entries
-- (not full line-by-line consolidation)
select
    consolidation_group,
    data_area_id,
    fiscal_year,
    fiscal_period,
    count(distinct main_account) as account_count
from {{ ref('gold_equity_method_associates') }}
group by consolidation_group, data_area_id, fiscal_year, fiscal_period
having count(distinct main_account) > 2
