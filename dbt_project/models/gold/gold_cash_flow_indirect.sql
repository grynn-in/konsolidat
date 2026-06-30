{{
    config(
        materialized='incremental',
        incremental_strategy='delete+insert',
        unique_key=['data_area_id', 'fiscal_year', 'fiscal_period'],
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# A2 / grynn-in/konsolidat#116: incremental-by-period materialization. A scoped
   orchestrator close (entity_scope / fiscal_year[ / fiscal_period] vars) narrows
   the SELECT to its slice; delete+insert keyed on the entity-period close slice
   (data_area_id, fiscal_year, fiscal_period) replaces only the in-scope keys and
   leaves every other entity/period intact, instead of OVERWRITING the table.
   No vars => every key present => identical to a full table build (opt-in). #}

{# Phase 6.1 — Entity-level cash flow statement (indirect method).

   Built from the SIGNED trial balance (gold_trial_balance), using the natural
   double-entry movement `period_debit - period_credit` per account. Unlike
   gold_bs_movement (which stores positive magnitudes via the period_net_amount
   measure — see grynn-in/konsolidat#64), the debit/credit split is genuinely
   signed, so the cash-flow sign falls out of the data instead of a hand-coded
   seed `sign`.

   Because the full trial balance is balanced double-entry, the signed movement
   over every account nets to zero each period:
       Σ(period_debit - period_credit) = 0  ⇒  Σ(cash) = −Σ(non-cash)
   so each non-cash account contributes `cash_flow_amount = −signed_movement`,
   and the activity total ties to the movement of the cash account(s) by
   construction — PROVIDED no non-cash account is dropped. We therefore
   categorize EVERY non-cash account:
     - P&L accounts (is_pnl = 1) collapse into one Operating "Net Income" line —
       the indirect-method starting point (net income = −Σ signed P&L movement).
     - Balance-sheet accounts in the seed use the seed's category/line (its
       `sign` column is ignored — the natural signs already do the work).
     - Any other non-cash account falls into an Operating
       "Other Non-Cash Adjustments" line so it is never dropped and the
       statement always ties.

   Net income is taken from the P&L accounts, NOT from the retained-earnings
   (3100) movement: in the demo books net income is not closed to RE during the
   year, so the RE account carries only equity movements (classified Financing).

   fiscal_period > 0 drops the opening-balance artifact rows (fiscal_year = 0 /
   fiscal_period = 0).

   Note: ClickHouse LEFT JOIN fills unmatched rows with the column default
   ('' for String, 0 for UInt8), not NULL — hence the '' / = 1 checks below.

   Grain: data_area_id × fiscal_year × fiscal_period × cf_category ×
   cf_line_item (individual P&L / adjustment accounts collapsed into their
   summary line). #}

with tb as (
    select
        data_area_id,
        fiscal_year,
        fiscal_period,
        main_account,
        is_pnl,
        period_debit - period_credit as signed_movement
    from {{ ref('gold_trial_balance') }}
    {# Orchestrator run filters (opt-in; no var => no predicate => full build).
       Cash flow is per-period, so both period and scope slicing are safe here. #}
    where fiscal_period > 0
        {{ period_filter() }}
        {{ scope_filter() }}
),

classified as (
    select
        t.data_area_id as data_area_id,
        t.fiscal_year as fiscal_year,
        t.fiscal_period as fiscal_period,
        t.is_pnl as is_pnl,
        t.signed_movement as signed_movement,
        cf.is_cash as seed_is_cash,
        cf.cf_category as seed_category,
        cf.cf_line_item as seed_line_item
    from tb as t
    left join {{ ref('cash_flow_categories') }} as cf
        on t.main_account = cf.main_account
),

lined as (
    select
        data_area_id,
        fiscal_year,
        fiscal_period,
        case
            when is_pnl = 1 then 'Operating'
            when seed_category != '' then seed_category
            else 'Operating'
        end as cf_category,
        case
            when is_pnl = 1 then 'Net Income'
            when seed_line_item != '' then seed_line_item
            else 'Other Non-Cash Adjustments'
        end as cf_line_item,
        -signed_movement as cash_flow_amount
    from classified
    where seed_is_cash = 0
)

select
    data_area_id,
    fiscal_year,
    fiscal_period,
    cf_category,
    cf_line_item,
    sum(cash_flow_amount) as cash_flow_amount,
    {# A3: stamp this run's scope so the confinement test can isolate the rows THIS
       close actually wrote from A2-preserved siblings (empty => full build). #}
    {{ close_scope_marker() }} as _close_scope
from lined
group by
    data_area_id,
    fiscal_year,
    fiscal_period,
    cf_category,
    cf_line_item
