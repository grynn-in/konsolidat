-- PRD-14 Test: Equity income = net_income × ownership_pct
-- The EQ_INCOME entry should match the formula
select
    ea.consolidation_group,
    ea.data_area_id,
    ea.fiscal_year,
    ea.fiscal_period,
    ea.amount as equity_income,
    ni.net_income,
    cg.ownership_pct / 100.0 as ownership_pct,
    ni.net_income * (cg.ownership_pct / 100.0) as expected
from {{ ref('gold_equity_method_associates') }} as ea
inner join (
    select
        tb.data_area_id,
        tb.fiscal_year,
        tb.fiscal_period,
        sum(tb.period_net_amount) as net_income
    from {{ ref('gold_trial_balance') }} as tb
    inner join {{ ref('silver_main_accounts') }} as ma
        on tb.main_account = ma.main_account_id
    where ma.is_pnl = 1
    group by tb.data_area_id, tb.fiscal_year, tb.fiscal_period
) as ni
    on ea.data_area_id = ni.data_area_id
    and ea.fiscal_year = ni.fiscal_year
    and ea.fiscal_period = ni.fiscal_period
inner join {{ ref('consolidation_groups') }} as cg
    on ea.data_area_id = cg.data_area_id
where ea.main_account = 'EQ_INCOME'
  and abs(ea.amount - ni.net_income * (cg.ownership_pct / 100.0)) > 0.01
