{{
    config(
        severity='warn'
    )
}}
-- Test: Per-dimension YTD at P12 should equal annual sum for that dimension.
-- Warns (not fails) because some dimension combos have no P12 posting,
-- so their YTD stops at an earlier period.
select
    ytd.data_area_id,
    ytd.fiscal_year,
    ytd.main_account,
    ytd.dim_cost_center,
    ytd.dim_department,
    ytd.dim_business_unit,
    ytd.ytd_net_amount as ytd_at_p12,
    annual.annual_total,
    abs(ytd.ytd_net_amount - annual.annual_total) as gap
from {{ ref('gold_ytd_trial_balance') }} as ytd
inner join (
    select
        data_area_id, fiscal_year, main_account,
        {{ dim_select() }},
        sum(period_net_amount) as annual_total
    from {{ ref('gold_trial_balance') }}
    group by data_area_id, fiscal_year, main_account, {{ dim_group_by() }}
) as annual
    on ytd.data_area_id = annual.data_area_id
    and ytd.fiscal_year = annual.fiscal_year
    and ytd.main_account = annual.main_account
    and ytd.dim_cost_center = annual.dim_cost_center
    and ytd.dim_department = annual.dim_department
    and ytd.dim_business_unit = annual.dim_business_unit
where ytd.fiscal_period = 12
  and abs(ytd.ytd_net_amount - annual.annual_total) > 0.01
