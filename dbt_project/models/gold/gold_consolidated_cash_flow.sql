{{
    config(
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# Phase 6.1 — Group-level cash flow statement (indirect method), built AFTER
   FX translation from gold_fully_consolidated_tb.

   gold_fully_consolidated_tb is a SIGNED, balanced trial balance: amounts carry
   natural debit/credit signs (revenue negative, expense positive) and the full
   set sums to ~0 per consolidation_group/period across all layers (entity + IC
   elimination + CTA + topside + equity-method + acquisition/disposal). This is
   different from gold_bs_movement, which the entity model uses and which stores
   positive magnitudes — so the entity seed `sign` is NOT reused here.

   Because the TB is signed and sums to zero, the change in cash equals the
   negative of every non-cash movement:
       Σ(all amounts) = 0  ⇒  Σ(cash) = −Σ(non-cash)
   so each non-cash account contributes `cash_flow_amount = −amount`, and the
   activity total ties to the movement of the cash account(s) by construction —
   PROVIDED no non-cash account is dropped. We therefore categorize EVERY
   non-cash account:
     - P&L accounts (silver is_pnl = 1) collapse into one Operating
       "Net Income (Consolidated)" line — the indirect-method starting point,
       net of topside P&L adjustments such as goodwill amortization.
     - Balance-sheet accounts in the seed use the seed's category/line (its
       `sign` is ignored — the natural signs already do the work).
     - Everything else non-cash (goodwill, CTA, IC, reclassifications, disposal)
       falls into an Operating "Consolidation and Non-Cash Adjustments" line so
       it is never dropped and the statement always ties.

   Note: ClickHouse LEFT JOIN fills unmatched rows with the column default
   ('' for String, 0 for UInt8), not NULL — hence the '' / = 1 checks below.

   Grain: consolidation_group × fiscal_year × fiscal_period × cf_category ×
   cf_line_item (data_area_id rolled up to the group; individual P&L /
   adjustment accounts collapsed into their summary line). #}

with fctb as (
    select
        consolidation_group,
        fiscal_year,
        fiscal_period,
        main_account,
        amount
    from {{ ref('gold_fully_consolidated_tb') }}
    where fiscal_period > 0
),

classified as (
    select
        f.consolidation_group as consolidation_group,
        f.fiscal_year as fiscal_year,
        f.fiscal_period as fiscal_period,
        f.amount as amount,
        cf.is_cash as seed_is_cash,
        cf.cf_category as seed_category,
        cf.cf_line_item as seed_line_item,
        ma.is_pnl as is_pnl
    from fctb as f
    left join {{ ref('cash_flow_categories') }} as cf
        on f.main_account = cf.main_account
    left join {{ ref('silver_main_accounts') }} as ma
        on f.main_account = ma.main_account_id
),

lined as (
    select
        consolidation_group,
        fiscal_year,
        fiscal_period,
        case
            when seed_category != '' then seed_category
            else 'Operating'
        end as cf_category,
        case
            when seed_line_item != '' then seed_line_item
            when is_pnl = 1 then 'Net Income (Consolidated)'
            else 'Consolidation and Non-Cash Adjustments'
        end as cf_line_item,
        -amount as cash_flow_amount
    from classified
    where seed_is_cash = 0
)

select
    consolidation_group,
    fiscal_year,
    fiscal_period,
    cf_category,
    cf_line_item,
    sum(cash_flow_amount) as cash_flow_amount
from lined
group by
    consolidation_group,
    fiscal_year,
    fiscal_period,
    cf_category,
    cf_line_item
