-- Test: YTD at P12 should equal the annual sum of period_net_amount
select
    ytd.data_area_id,
    ytd.fiscal_year,
    ytd.main_account,
    ytd.ytd_net_amount as ytd_at_p12,
    annual.annual_total,
    abs(ytd.ytd_net_amount - annual.annual_total) as gap
from {{ ref('gold_ytd_trial_balance') }} as ytd
inner join (
    select
        data_area_id, fiscal_year, main_account,
        sum(period_net_amount) as annual_total
    from {{ ref('gold_trial_balance') }}
    group by data_area_id, fiscal_year, main_account
) as annual
    on ytd.data_area_id = annual.data_area_id
    and ytd.fiscal_year = annual.fiscal_year
    and ytd.main_account = annual.main_account
where ytd.fiscal_period = 12
  and abs(ytd.ytd_net_amount - annual.annual_total) > 0.01
