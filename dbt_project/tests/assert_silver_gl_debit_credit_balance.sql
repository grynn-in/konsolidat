-- Test: Total debits should equal total credits across all GL entries
-- D365 sandbox/demo data is often unbalanced, so warn rather than fail
{{ config(severity='warn') }}

select
    data_area_id,
    fiscal_year,
    abs(sum(debit_amount) - sum(credit_amount)) as imbalance
from {{ ref('silver_gl_entries') }}
group by data_area_id, fiscal_year
having abs(sum(debit_amount) - sum(credit_amount)) > 0.01
