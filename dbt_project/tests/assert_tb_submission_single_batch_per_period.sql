{#
    At most ONE claimed batch per (entity, fiscal_year, fiscal_period).

    Two claimed batches for the same entity-period flow ADDITIVELY into
    silver_gl_entries and gold sums them — each batch balancing individually,
    so no balance test can see the double-count. konsol refuses a second
    submission while one is submitted; this is the warehouse-side guarantee
    for rows that arrived any other way.
#}

select
    data_area_id,
    fiscal_year,
    fiscal_period,
    count(distinct batch_id) as claimed_batches,
    groupArray(batch_id) as batch_ids
from {{ ref('bronze_trial_balance_submissions') }}
group by data_area_id, fiscal_year, fiscal_period
having claimed_batches > 1
