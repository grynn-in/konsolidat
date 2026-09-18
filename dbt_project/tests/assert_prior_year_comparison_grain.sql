{#
    konsol#159 / #175 review B1, re-review F1: gold_prior_year_comparison keeps
    one row per (entity, year, period, account, dimensions). With a row per
    intercompany partner, each current row joined every prior-year partner row
    (300 instead of 150).

    Refs this model only, so a build picks the test exactly when it builds the
    model (see assert_ytd_trial_balance_grain).
#}

select
    data_area_id, fiscal_year, fiscal_period, main_account, {{ dim_select(trailing=true) }}
    count() as rows_per_key
from {{ ref('gold_prior_year_comparison') }}
group by data_area_id, fiscal_year, fiscal_period, main_account{{ dim_group_by(leading=true) }}
having count() > 1
