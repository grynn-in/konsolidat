-- Test: Total debits should equal total credits across all GL entries.
-- Since konsolidat#112, silver derives debit/credit from the SIGN of the
-- (already-balanced) accounting amount, every voucher nets to zero by
-- construction. Escalated to error (konsolidat#118) — verified PASS against
-- live data 2026-06-29. An unbalanced entity now fails the governed build.
{{ config(severity='error') }}

select
    data_area_id,
    fiscal_year,
    abs(sum(debit_amount) - sum(credit_amount)) as imbalance
from {{ ref('silver_gl_entries') }}
group by data_area_id, fiscal_year
having abs(sum(debit_amount) - sum(credit_amount)) > 0.01
