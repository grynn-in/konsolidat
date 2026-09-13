{#
    #175 third review L1: the cash flow's net income is the group view's
    consolidated P&L, every layer included.

    The group view's P&L is gold_fully_consolidated_tb's P&L accounts (silver
    is_pnl = 1), per group and period. The statement reports them on its
    "Net Income (Consolidated)" line, except an account the cash-flow mapping
    gives a line of its own (a Published row with a line item), which is
    reported there. So those accounts are left out of both sides.

    It fails when the statement drops a P&L entry. The case it was written
    for: the minority's part of a P&L pair's elimination (decision 12, the
    group view's 'nci' entries, ic_elimination_nci) is in the P&L, and the
    statement once left it out with the balance-sheet pairs' ones.
#}

with mapped_lines as (
    select distinct main_account
    from {{ source('epm_staging', 'cash_flow_categories') }}
    where status = 'Published' and cf_line_item != ''
),

group_pnl as (
    select f.consolidation_group as consolidation_group, f.fiscal_year as fiscal_year,
           f.fiscal_period as fiscal_period, ifNull(f.amount, 0) as pnl, toFloat64(0) as net_income
    from {{ ref('gold_fully_consolidated_tb') }} as f
    inner join {{ ref('silver_main_accounts') }} as ma
        on ma.main_account_id = f.main_account
    where f.fiscal_period > 0
      and ma.is_pnl = 1
      and f.main_account not in (select main_account from mapped_lines)
),

statement as (
    select consolidation_group, fiscal_year, fiscal_period, toFloat64(0), -cash_flow_amount
    from {{ ref('gold_consolidated_cash_flow') }}
    where cf_line_item = 'Net Income (Consolidated)'
)

select consolidation_group, fiscal_year, fiscal_period,
       sum(pnl) as group_view_pnl, sum(net_income) as statement_net_income
from (select * from group_pnl union all select * from statement)
group by consolidation_group, fiscal_year, fiscal_period
having abs(sum(pnl) - sum(net_income)) >= 0.01
