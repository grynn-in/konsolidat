{#
    konsol#159 / #175 review (B1, B2): the partner column must not fan out any
    per-account figure. With several partners on one account, a join or a
    running sum keyed without the partner multiplies it: 300 instead of 150
    year on year, 250 instead of 150 YTD.

    1. tb_grain: one gold_trial_balance row per (entity, year, period, account,
       dimensions).
    2. consolidated_ytd: the entity layer of gold_consolidated_ytd is the true
       cumulative group amount of gold_consolidated_trial_balance summed to the
       account grain.

    Every model here rebuilds in the consolidation build scope
    (+tag:domain:consolidation), which picks this test whenever a trial
    balance is submitted (#175 re-review F1). gold_ytd_trial_balance and
    gold_prior_year_comparison do not rebuild there, so their grain is checked
    by single-model tests (assert_ytd_trial_balance_grain,
    assert_prior_year_comparison_grain), picked only when their model is.
#}

with tb_grain as (
    select
        'tb_grain' as failed_check, '' as consolidation_group,
        data_area_id, fiscal_year, fiscal_period, main_account,
        toFloat64(count()) as got, toFloat64(1) as expected
    from {{ ref('gold_trial_balance') }}
    group by data_area_id, fiscal_year, fiscal_period, main_account{{ dim_group_by(leading=true) }}
    having count() > 1
),

group_net as (
    select
        consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account, {{ dim_select(trailing=true) }}
        ifNull(toFloat64(sum(group_amount)), 0) as amount_total
    from {{ ref('gold_consolidated_trial_balance') }}
    group by consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account{{ dim_group_by(leading=true) }}
),

cytd_parts as (
    select consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account, {{ dim_select(trailing=true) }}
           ifNull(toFloat64(ytd_amount), 0) as got, toFloat64(0) as expected
    from {{ ref('gold_consolidated_ytd') }}
    where adjustment_type = 'entity'
    union all
    select consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account, {{ dim_select(trailing=true) }}
           toFloat64(0),
           sum(amount_total) over (
               partition by consolidation_group, data_area_id, fiscal_year, main_account{{ dim_partition_by(leading=true) }}
               order by fiscal_period
               rows between unbounded preceding and current row
           )
    from group_net
),

cytd_check as (
    select
        'consolidated_ytd' as failed_check, consolidation_group,
        data_area_id, fiscal_year, fiscal_period, main_account,
        sum(got) as got_total, sum(expected) as expected_total
    from cytd_parts
    group by consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account{{ dim_group_by(leading=true) }}
    having abs(got_total - expected_total) > 0.01
)

select * from tb_grain
union all
select * from cytd_check
