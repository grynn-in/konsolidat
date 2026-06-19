-- Phase 6.1 Test (AC#4): per data_area_id / fiscal_year / fiscal_period, the
-- sum of Operating + Investing + Financing cash flows must equal the net change
-- in cash (the period movement of is_cash = 1 accounts), within +/- 0.01.
--
-- This holds only when the balance sheet balances each period (Assets =
-- Liabilities + Equity). A failure on demo data is a data issue (the BS does
-- not balance), not a model bug — exactly what the Phase 6.10 assertion suite
-- exists to surface.
with activity as (
    select
        data_area_id,
        fiscal_year,
        fiscal_period,
        sum(cash_flow_amount) as total_activity
    from {{ ref('gold_cash_flow_indirect') }}
    group by data_area_id, fiscal_year, fiscal_period
),

cash_change as (
    select
        m.data_area_id as data_area_id,
        m.fiscal_year as fiscal_year,
        m.fiscal_period as fiscal_period,
        sum(m.period_movement) as net_cash_change
    from {{ ref('gold_bs_movement') }} as m
    inner join {{ ref('cash_flow_categories') }} as cf
        on m.main_account = cf.main_account
    where cf.is_cash = 1
        and m.fiscal_period > 0
    group by m.data_area_id, m.fiscal_year, m.fiscal_period
)

select
    coalesce(a.data_area_id, c.data_area_id) as data_area_id,
    coalesce(a.fiscal_year, c.fiscal_year) as fiscal_year,
    coalesce(a.fiscal_period, c.fiscal_period) as fiscal_period,
    coalesce(a.total_activity, 0) as total_activity,
    coalesce(c.net_cash_change, 0) as net_cash_change
from activity as a
full outer join cash_change as c
    on a.data_area_id = c.data_area_id
    and a.fiscal_year = c.fiscal_year
    and a.fiscal_period = c.fiscal_period
where abs(coalesce(a.total_activity, 0) - coalesce(c.net_cash_change, 0)) > 0.01
