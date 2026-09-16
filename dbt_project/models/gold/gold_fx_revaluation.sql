{{
    config(
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# PRD-2: CTA (Currency Translation Adjustment) — the residual plug that
   restores the translated trial balance to balance.

   Each entity's LOCAL trial balance is balanced double-entry (Σ of the signed
   debit−credit movement = 0). After translating account types at different
   rates (balance sheet at closing, P&L at average, equity at historical), the
   translated balances no longer sum to zero. CTA is exactly the negative of
   that residual, so for each entity/period:  Σ(translated) + CTA = 0  — the
   consolidated balance sheet balances by construction (IAS 21).

   This replaces the earlier formula that approximated CTA as only the P&L
   timing component Σ(P&L × (closing − average)). That term is ~0 here (the
   closing/average spread is ~0.00006) and never captured the real balance-sheet
   retranslation difference, so the consolidated TB did not balance for
   multi-currency groups (#66).

   CTA is computed on the GROUP's share (group_amount); the NCI share of the
   translation difference rides with nci_amount and is handled by the NCI
   schedule. A same-currency entity translates at 1.0, so its residual — and
   therefore its CTA — is zero.

   CTA is a WHOLE-ENTITY residual, never a per-account figure. This model emits
   one plug row per entity/period carrying the literal 'CTA' in main_account —
   no account code ever appears in that column — and the residual is
   -sum(group_amount) over ALL accounts, historical-rate accounts included:
   nothing excludes them, so an account declared at the historical rate does
   contribute to it. There is therefore no per-account CTA rule to assert here.
   konsolidat#213 retired assert_equity_historical_no_cta on that ground. It
   filtered this model on `main_account in (select main_account_id from
   silver_main_accounts where …)`, which the literal 'CTA' can never match, so
   the test passed on any data and could never fail; its premise — that
   historical-rate accounts are excluded from CTA — was false against this
   model besides. #}

with entity_residual as (
    select
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        any(accounting_currency) as accounting_currency,
        any(reporting_currency) as reporting_currency,
        any(closing_rate) as closing_rate,
        any(average_rate) as average_rate,
        {# Plug = −(sum of translated group-share amounts across all accounts) #}
        -sum(group_amount) as cta_amount
    from {{ ref('gold_consolidated_trial_balance') }}
    group by
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period
)

select
    consolidation_group,
    data_area_id,
    fiscal_year,
    fiscal_period,
    reporting_currency,
    accounting_currency,
    'CTA' as adjustment_type,
    'CTA' as main_account,
    closing_rate,
    average_rate,
    cta_amount
from entity_residual
