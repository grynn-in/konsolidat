{{
    config(
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# Phase 6.1 — Group-level cash flow statement (indirect method), built AFTER
   FX translation from gold_fully_consolidated_tb (entity translated balances +
   IC eliminations + CTA + topside + equity-method + acquisition/disposal).

   gold_fully_consolidated_tb.amount is a per-period flow (it ultimately derives
   from period_net_amount in gold_consolidated_trial_balance), so for a BS
   account the amount IS the period movement — no consecutive-period delta is
   needed. We net all layers per account per period, then categorize via the
   cash_flow_categories seed exactly like the entity model.

   CTA / IC-elimination treatment (PRD open question #2): each layer's amount is
   folded into the underlying main_account, so a CTA revaluation of a fixed
   asset lands in that account's category. This keeps the statement tied to the
   change in *translated* cash whenever the consolidated BS balances (the same
   condition assert_end_to_end_bs_balances enforces). Rows whose main_account is
   not a BS account in the seed (e.g. the synthetic 'DISPOSAL' line) are dropped
   by the inner join — disposal gain/loss is out of scope for this PRD.

   Reconciliation target: movement of is_cash = 1 accounts across all layers —
   see tests/assert_consolidated_cf_reconciles.sql.

   Grain: consolidation_group x fiscal_year x fiscal_period x cf_category x
   cf_line_item x main_account (data_area_id rolled up to the group). #}

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

categorized as (
    select
        f.consolidation_group as consolidation_group,
        f.fiscal_year as fiscal_year,
        f.fiscal_period as fiscal_period,
        cf.cf_category as cf_category,
        cf.cf_line_item as cf_line_item,
        f.main_account as main_account,
        f.amount * cf.sign as cash_flow_amount
    from fctb as f
    inner join {{ ref('cash_flow_categories') }} as cf
        on f.main_account = cf.main_account
    where cf.is_cash = 0
)

select
    consolidation_group,
    fiscal_year,
    fiscal_period,
    cf_category,
    cf_line_item,
    main_account,
    sum(cash_flow_amount) as cash_flow_amount
from categorized
group by
    consolidation_group,
    fiscal_year,
    fiscal_period,
    cf_category,
    cf_line_item,
    main_account
