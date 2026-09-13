{#
    konsol#159 / #175 review (B1, B2): the partner column must not fan out any
    per-account figure. With several partners on one account, a join or a
    running sum keyed without the partner multiplies it: 300 instead of 150
    year on year, 250 instead of 150 YTD.

    The expected figures come from silver_gl_entries and
    gold_consolidated_trial_balance summed to the account grain, not from
    gold_trial_balance, so this still fails if gold_trial_balance itself
    regains a row per partner.

    1. tb_grain: one gold_trial_balance row per (entity, year, period, account,
       dimensions).
    2. ytd: gold_ytd_trial_balance's ytd_net_amount is the true cumulative net.
    3. prior_year: gold_prior_year_comparison's current and prior-year amounts
       are the true net of the period, this year and last year.
    4. consolidated_ytd: the entity layer of gold_consolidated_ytd is the true
       cumulative group amount.
#}

with net as (
    select
        data_area_id, fiscal_year, fiscal_period, main_account, {{ dim_select() }},
        toFloat64(sum(debit_amount) - sum(credit_amount)) as net_amount
    from {{ ref('silver_gl_entries') }}
    group by data_area_id, fiscal_year, fiscal_period, main_account, {{ dim_group_by() }}
),

tb_grain as (
    select
        'tb_grain' as failed_check, '' as consolidation_group,
        data_area_id, fiscal_year, fiscal_period, main_account,
        toFloat64(count()) as got, toFloat64(1) as expected
    from {{ ref('gold_trial_balance') }}
    group by data_area_id, fiscal_year, fiscal_period, main_account, {{ dim_group_by() }}
    having count() > 1
),

ytd_parts as (
    select data_area_id, fiscal_year, fiscal_period, main_account, {{ dim_select() }},
           toFloat64(ytd_net_amount) as got, toFloat64(0) as expected
    from {{ ref('gold_ytd_trial_balance') }}
    union all
    select data_area_id, fiscal_year, fiscal_period, main_account, {{ dim_select() }},
           toFloat64(0),
           sum(net_amount) over (
               partition by data_area_id, fiscal_year, main_account, {{ dim_partition_by() }}
               order by fiscal_period
               rows between unbounded preceding and current row
           )
    from net
),

ytd_check as (
    select
        'ytd' as failed_check, '' as consolidation_group,
        data_area_id, fiscal_year, fiscal_period, main_account,
        sum(got) as got_total, sum(expected) as expected_total
    from ytd_parts
    group by data_area_id, fiscal_year, fiscal_period, main_account, {{ dim_group_by() }}
    having abs(got_total - expected_total) > 0.01
),

{# net is one row per key, so this join cannot fan out; a miss (no prior year)
   comes back as 0 under join_use_nulls=0, as the model's coalesce does. #}
py_expected as (
    select
        c.data_area_id as data_area_id, c.fiscal_year as fiscal_year,
        c.fiscal_period as fiscal_period, c.main_account as main_account,
        {% for d in var('dimensions') %}c.{{ d.name }} as {{ d.name }},{% endfor %}
        c.net_amount as current_net,
        p.net_amount as prior_net
    from net as c
    left join net as p
        on c.data_area_id = p.data_area_id
        and c.fiscal_year = p.fiscal_year + 1
        and c.fiscal_period = p.fiscal_period
        and c.main_account = p.main_account
        {{ dim_join_on('c', 'p') }}
),

py_parts as (
    select data_area_id, fiscal_year, fiscal_period, main_account, {{ dim_select() }},
           toFloat64(current_amount) as got_current, toFloat64(0) as expected_current,
           toFloat64(prior_year_amount) as got_prior, toFloat64(0) as expected_prior
    from {{ ref('gold_prior_year_comparison') }}
    union all
    select data_area_id, fiscal_year, fiscal_period, main_account, {{ dim_select() }},
           toFloat64(0), current_net, toFloat64(0), prior_net
    from py_expected
),

py_check as (
    select
        'prior_year' as failed_check, '' as consolidation_group,
        data_area_id, fiscal_year, fiscal_period, main_account,
        sum(got_prior) as got_total, sum(expected_prior) as expected_total
    from py_parts
    group by data_area_id, fiscal_year, fiscal_period, main_account, {{ dim_group_by() }}
    having abs(sum(got_current) - sum(expected_current)) > 0.01
        or abs(sum(got_prior) - sum(expected_prior)) > 0.01
),

group_net as (
    select
        consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account, {{ dim_select() }},
        toFloat64(sum(group_amount)) as amount_total
    from {{ ref('gold_consolidated_trial_balance') }}
    group by consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account, {{ dim_group_by() }}
),

cytd_parts as (
    select consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account, {{ dim_select() }},
           toFloat64(ytd_amount) as got, toFloat64(0) as expected
    from {{ ref('gold_consolidated_ytd') }}
    where adjustment_type = 'entity'
    union all
    select consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account, {{ dim_select() }},
           toFloat64(0),
           sum(amount_total) over (
               partition by consolidation_group, data_area_id, fiscal_year, main_account, {{ dim_partition_by() }}
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
    group by consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account, {{ dim_group_by() }}
    having abs(got_total - expected_total) > 0.01
)

select * from tb_grain
union all
select * from ytd_check
union all
select * from py_check
union all
select * from cytd_check
