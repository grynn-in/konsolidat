{#
    Every claimed trial-balance batch must balance: sum(debit) = sum(credit)
    within a small rounding tolerance.

    konsol validates this before a submission can be submitted (on the SAME
    rounded-to-cents values that land here), so a failure means rows were
    landed or altered outside the doctype flow. Defense in depth for the one
    property that makes a trial balance a trial balance.

    Aliases are defined once and reused — the displayed difference is by
    construction the number the HAVING fired on.
#}

select
    batch_id,
    any(submission_name) as submission_name,
    round(sum(debit_amount), 2) as total_debit,
    round(sum(credit_amount), 2) as total_credit,
    total_debit - total_credit as difference
from {{ ref('bronze_trial_balance_submissions') }}
group by batch_id
having abs(difference) > 0.01
