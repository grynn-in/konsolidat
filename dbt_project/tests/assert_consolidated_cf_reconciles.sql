-- Phase 6.1 Test (AC#5): at group grain, per consolidation_group / fiscal_year /
-- fiscal_period, the sum of Operating + Investing + Financing cash flows must
-- equal the net change in (translated) cash — the movement of is_cash = 1
-- accounts across all consolidation layers — within +/- 0.01.
--
-- Holds whenever the fully consolidated balance sheet balances each period
-- (see assert_end_to_end_bs_balances). CTA is the plug that restores the BS
-- identity after per-account-type translation, so including every layer's cash
-- effect on both sides keeps the statement tied.
with activity as (
    select
        consolidation_group,
        fiscal_year,
        fiscal_period,
        sum(cash_flow_amount) as total_activity
    from {{ ref('gold_consolidated_cash_flow') }}
    group by consolidation_group, fiscal_year, fiscal_period
),

cash_change as (
    select
        f.consolidation_group as consolidation_group,
        f.fiscal_year as fiscal_year,
        f.fiscal_period as fiscal_period,
        sum(f.amount) as net_cash_change
    from {{ ref('gold_fully_consolidated_tb') }} as f
    inner join {{ ref('cash_flow_categories') }} as cf
        on f.main_account = cf.main_account
    where cf.is_cash = 1
        and f.fiscal_period > 0
    group by f.consolidation_group, f.fiscal_year, f.fiscal_period
)

select
    coalesce(a.consolidation_group, c.consolidation_group) as consolidation_group,
    coalesce(a.fiscal_year, c.fiscal_year) as fiscal_year,
    coalesce(a.fiscal_period, c.fiscal_period) as fiscal_period,
    coalesce(a.total_activity, 0) as total_activity,
    coalesce(c.net_cash_change, 0) as net_cash_change
from activity as a
full outer join cash_change as c
    on a.consolidation_group = c.consolidation_group
    and a.fiscal_year = c.fiscal_year
    and a.fiscal_period = c.fiscal_period
where abs(coalesce(a.total_activity, 0) - coalesce(c.net_cash_change, 0)) > 0.01
