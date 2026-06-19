{{
    config(
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# Phase 6.1 — Entity-level cash flow statement (indirect method).

   Built purely from balance-sheet account movements (gold_bs_movement). Each
   non-cash BS account's period_movement is converted to a cash effect via the
   cash_flow_categories seed (cash_flow_amount = period_movement * sign) and
   classified into Operating / Investing / Financing.

   Net income is NOT pulled separately from gold_pnl_by_period — that would
   double-count, because the retained-earnings (3100) movement already captures
   period net income on the balance sheet. RE movement is categorized as the
   Operating "Net Income" line; dividends declared (3200) flow to Financing.

   Balances are positive magnitudes, so the sign is explicit per account in the
   seed rather than relying on signed debit/credit. Given the BS identity
   (Assets = Liabilities + Equity) holds each period, the signed sum over all
   non-cash accounts equals the movement of the cash account(s) — see
   tests/assert_cf_categories_equal_net_change.sql. Cash accounts (is_cash = 1)
   are excluded from the activity lines and define that reconciliation target.

   fiscal_period > 0 drops the opening-balance artifact rows (fiscal_year = 0 /
   fiscal_period = 0) that would otherwise skew the totals.

   Grain: data_area_id x fiscal_year x fiscal_period x cf_category x
   cf_line_item x main_account. gold_bs_movement carries dimension columns; this
   model sums period_movement across them to report whole-account movements. #}

with movements as (
    select
        data_area_id,
        fiscal_year,
        fiscal_period,
        main_account,
        period_movement
    from {{ ref('gold_bs_movement') }}
    where fiscal_period > 0
),

categorized as (
    select
        m.data_area_id as data_area_id,
        m.fiscal_year as fiscal_year,
        m.fiscal_period as fiscal_period,
        cf.cf_category as cf_category,
        cf.cf_line_item as cf_line_item,
        m.main_account as main_account,
        m.period_movement * cf.sign as cash_flow_amount
    from movements as m
    inner join {{ ref('cash_flow_categories') }} as cf
        on m.main_account = cf.main_account
    where cf.is_cash = 0
)

select
    data_area_id,
    fiscal_year,
    fiscal_period,
    cf_category,
    cf_line_item,
    main_account,
    sum(cash_flow_amount) as cash_flow_amount
from categorized
group by
    data_area_id,
    fiscal_year,
    fiscal_period,
    cf_category,
    cf_line_item,
    main_account
