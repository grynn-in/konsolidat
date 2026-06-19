-- Phase 6.1 Test (AC#4): per data_area_id / fiscal_year / fiscal_period, the
-- sum of Operating + Investing + Financing cash flows must equal the net change
-- in cash (the signed movement of is_cash = 1 accounts), within +/- 0.01.
--
-- This holds by construction: gold_cash_flow_indirect sums −(period_debit −
-- period_credit) over every non-cash account, and the full trial balance is
-- balanced double-entry, so Σ(cash) = −Σ(non-cash). A failure would mean a
-- non-cash account was dropped or the books are not balanced for that period
-- (a data issue surfaced by the Phase 6.10 assertion suite, not a model bug).
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
        t.data_area_id as data_area_id,
        t.fiscal_year as fiscal_year,
        t.fiscal_period as fiscal_period,
        sum(t.period_debit - t.period_credit) as net_cash_change
    from {{ ref('gold_trial_balance') }} as t
    inner join {{ ref('cash_flow_categories') }} as cf
        on t.main_account = cf.main_account
    where cf.is_cash = 1
        and t.fiscal_period > 0
    group by t.data_area_id, t.fiscal_year, t.fiscal_period
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
