{# grynn-in/konsolidat#109 — translation_rate must never be 0.

   A translation_rate of exactly 0 means a currency pair had no quote in either
   direction and the rate_lookup `coalesce(..., 1.0)` fallback failed to fire:
   the LEFT-join miss defaulted the rate column to 0 (join_use_nulls=0) instead
   of NULL, so the entity's translated_amount / group_amount / nci_amount all
   silently collapsed to $0. The fix casts the rate-lookup CTEs to Nullable so a
   genuine miss yields NULL and the 1.0 fallback fires. This test fails loudly if
   that regresses (or if any future fully-unquoted pair slips through).

   A valid FX rate is never 0; same-currency rows short-circuit to 1.0 upstream. #}

select
    consolidation_group,
    data_area_id,
    accounting_currency,
    reporting_currency,
    fiscal_year,
    fiscal_period,
    translation_rate
from {{ ref('gold_consolidated_trial_balance') }}
where translation_rate = 0
