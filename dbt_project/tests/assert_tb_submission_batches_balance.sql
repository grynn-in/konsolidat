{#
    Every claimed trial-balance batch must balance: sum(debit) = sum(credit)
    within a small rounding tolerance.

    konsol validates this before a submission can be submitted, so a failure
    here means rows were landed or altered outside the doctype flow — a manual
    INSERT, a partial landing that somehow got claimed, a mutation. Defense in
    depth for the one property that makes a trial balance a trial balance.
#}

select
    batch_id,
    any(submission_name) as submission_name,
    round(sum(debit_amount), 2) as total_debit,
    round(sum(credit_amount), 2) as total_credit,
    round(sum(debit_amount) - sum(credit_amount), 2) as difference
from {{ ref('bronze_trial_balance_submissions') }}
group by batch_id
having abs(sum(debit_amount) - sum(credit_amount)) > 0.01
