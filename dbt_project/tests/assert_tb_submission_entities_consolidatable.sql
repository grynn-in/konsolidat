{#
    Every entity with a claimed submission must exist in silver_legal_entities.

    gold_consolidated_trial_balance INNER JOINs silver_legal_entities (ERP-
    sourced) for the accounting currency, so a submission-only entity with no
    row there is silently DROPPED at the consolidation chokepoint: the
    submission looks successful, gold_trial_balance carries it, and the
    consolidated statements simply omit the entity with nothing failing.

    Until connector-less entities have a governed registry of their own (see
    the follow-up issue on Entity write-through), F8 serves entities the
    warehouse already knows — and this test turns the silent understatement
    into a loud, named failure.
#}

select
    tbs.data_area_id,
    any(tbs.submission_name) as submission_name
from {{ ref('bronze_trial_balance_submissions') }} as tbs
left join {{ ref('silver_legal_entities') }} as le
    on tbs.data_area_id = le.data_area
where coalesce(le.data_area, '') = ''
group by tbs.data_area_id
