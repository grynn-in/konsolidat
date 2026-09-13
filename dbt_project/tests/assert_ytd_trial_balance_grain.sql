{#
    konsol#159 / #175 review B2, re-review F1: gold_ytd_trial_balance keeps one
    row per (entity, year, period, account, dimensions). With a row per
    intercompany partner, each got a partial running total (250 instead of 150).

    Refs this model only, so a build picks the test exactly when it builds the
    model: the consolidation scope does not rebuild it, and a test comparing
    it with a model that scope does rebuild failed every trial balance
    submission's build against a stale table.
#}

select
    data_area_id, fiscal_year, fiscal_period, main_account, {{ dim_select() }},
    count() as rows_per_key
from {{ ref('gold_ytd_trial_balance') }}
group by data_area_id, fiscal_year, fiscal_period, main_account, {{ dim_group_by() }}
having count() > 1
