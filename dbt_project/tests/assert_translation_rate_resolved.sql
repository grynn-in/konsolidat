{# grynn-in/konsolidat#109, #194 — every consolidated row must carry a resolved FX rate.

   Two failure modes, both of which silently misstate translated balances:

   1. translation_rate = 0  — a LEFT-join miss defaulted the rate column to 0
      (join_use_nulls=0) and the entity's translated/group/nci amounts collapse
      to $0. (The original #109.)

   2. translation_rate IS NULL — defensive: a Nullable rate that escaped every
      rate branch would evade a bare `= 0` check (NULL = 0 -> NULL).

   A cross-currency row translating at exactly 1.0 is NOT a failure (#194):
   near-parity pairs are quoted to 3 decimals, so 1.000 is a legitimate approved
   rate. The model has no parity fallback — a translated currency with no
   approved rate stops the build (throwIf in gold_consolidated_trial_balance)
   before this test runs — so 1.0 here can only be a real quote.

   A green result means every entity/period translated with a resolved rate. #}

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
    or translation_rate is null
