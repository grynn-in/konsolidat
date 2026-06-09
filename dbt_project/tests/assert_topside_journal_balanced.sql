-- PRD-5 Test: Each top-side journal must be balanced (debits = credits)
select
    journal_id,
    sum(debit_amount) as total_debit,
    sum(credit_amount) as total_credit,
    abs(sum(debit_amount) - sum(credit_amount)) as imbalance
from {{ ref('gold_consolidation_adjustments') }}
group by journal_id
having abs(sum(debit_amount) - sum(credit_amount)) > 0.01
