{# grynn-in/konsolidat#109 — every consolidated row must resolve a REAL FX rate.

   Three failure modes, all of which silently misstate translated balances:

   1. translation_rate = 0  — a LEFT-join miss defaulted the rate column to 0
      (join_use_nulls=0) and short-circuited coalesce before the fallback. The
      entity's translated/group/nci amounts collapse to $0. (The original #109.)

   2. translation_rate IS NULL — defensive: a Nullable rate that escaped every
      coalesce branch would evade a bare `= 0` check (NULL = 0 -> NULL).

   3. A CROSS-currency row (accounting != reporting) translating at exactly 1.0
      — that is the parity fallback firing, i.e. the pair had NO quote of any
      type (Closing, Average, or Default) as-of the period. A genuine market
      rate between two distinct currencies is never exactly 1.000000, so this
      means a real missing-rate data gap that must FAIL LOUDLY rather than be
      papered over at 1:1 (which is what masked JPY->USD before 2014 as ~100x).
      Same-currency rows legitimately short-circuit to 1.0 and are excluded.

   A green result means every entity/period translated with a real, resolved
   rate. #}

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
    or (accounting_currency != reporting_currency and translation_rate = 1.0)
