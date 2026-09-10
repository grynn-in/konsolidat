{#
    Every claimed batch must hold exactly the row count its claim recorded.

    The claim is written AFTER the rows land, carrying konsol's count — so a
    partial landing that somehow got claimed (or rows deleted/duplicated
    afterwards) shows up as a count mismatch here. This is the check the
    control table's row_count column exists to enable.
#}

select
    batch_id,
    any(submission_name) as submission_name,
    any(claimed_row_count) as rows_claimed,
    count() as rows_present
from {{ ref('bronze_trial_balance_submissions') }}
group by batch_id
having rows_present != rows_claimed
