{#
    An entity's claimed trial-balance batches all declare the SAME amount basis (konsolidat#199).

    silver_tb_movements normalises each batch to period movements from its
    declared basis, and the rules for 'Year-to-date movement' and
    'Period-end balance' difference a period against the entity's previous
    period. That difference only means something when both periods speak the
    same language: a balance minus a movement is nothing. The model does not
    try to reconcile a mixed history; it computes each period with that
    period's own basis, so a mix would be wrong quietly. This is an error: the
    build stops and names the entity and its bases until every batch declares
    one basis (re-upload the odd batches with the right one).

    Empty bases are not counted here; assert_tb_submission_has_basis names them.
#}

{{ config(severity='error') }}

select
    data_area_id,
    groupUniqArray(amount_basis) as bases
from {{ ref('bronze_trial_balance_submissions') }}
where amount_basis != ''
group by data_area_id
having uniqExact(amount_basis) > 1
