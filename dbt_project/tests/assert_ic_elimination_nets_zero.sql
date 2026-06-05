-- Test: Sum of all IC eliminations must net to zero
-- Debit eliminations + credit eliminations = 0
select
    consolidation_group,
    fiscal_year,
    fiscal_period,
    sum(debit_elimination + credit_elimination) as net_elimination
from {{ ref('gold_ic_eliminations') }}
group by consolidation_group, fiscal_year, fiscal_period
having abs(sum(debit_elimination + credit_elimination)) > 0.01
