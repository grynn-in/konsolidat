-- Test: Total debits must equal total credits across all GL entries
-- This is a fundamental accounting invariant
select
    data_area_id,
    fiscal_year,
    abs(sum(debit_amount) - sum(credit_amount)) as imbalance
from {{ ref('silver_gl_entries') }}
group by data_area_id, fiscal_year
having abs(sum(debit_amount) - sum(credit_amount)) > 0.01
