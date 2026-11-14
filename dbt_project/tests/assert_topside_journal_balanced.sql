-- PRD-5 Test: Each top-side journal must be balanced (debits = credits).
--
-- konsol#353 follow-up: the tolerance is one unit of the journal currency's
-- minor unit (USD 0.01, BHD 0.001, JPY 1), not a flat 0.01. The materiality
-- floor is currency-scaled (Deepak Pai, 18 Sep 2026, konsolidat#209; a flat
-- default was rejected). The journal's currency is its group's reporting
-- currency (the root row, data_area_id ''), and its minor unit is the
-- currencies row konsol writes from ISO Currency.
--
-- A journal whose group declares no reporting currency with a minor unit has
-- nothing to be judged by, so it is reported (reason 'no currency'), never
-- judged at a default. join_use_nulls=0 would read a missing minor unit as 0
-- (a tolerance of 1), so the two cases are a UNION ALL with an INNER JOIN and
-- a NOT IN, never a LEFT JOIN.
with journals as (
    select
        consolidation_group,
        journal_id,
        sum(debit_amount) as total_debit,
        sum(credit_amount) as total_credit
    from {{ ref('gold_consolidation_adjustments') }}
    group by consolidation_group, journal_id
),

units as (
    select
        g.consolidation_group as consolidation_group,
        any(g.reporting_currency) as currency,
        any(c.minor_unit) as minor_unit
    from {{ source('epm_gold', 'consolidation_groups') }} as g
    inner join {{ source('epm_gold', 'currencies') }} as c
        on c.currency_code = g.reporting_currency
    where g.data_area_id = ''
    group by g.consolidation_group
)

select
    j.journal_id as journal_id,
    j.consolidation_group as consolidation_group,
    u.currency as currency,
    j.total_debit as total_debit,
    j.total_credit as total_credit,
    abs(j.total_debit - j.total_credit) as imbalance,
    'out of balance by more than one minor unit' as reason
from journals as j
inner join units as u on u.consolidation_group = j.consolidation_group
-- pow() is a Float64: 1e-12 keeps an imbalance of exactly one unit inside it.
where toFloat64(abs(j.total_debit - j.total_credit)) > pow(10, -toInt32(u.minor_unit)) + 1e-12

union all

select
    j.journal_id as journal_id,
    j.consolidation_group as consolidation_group,
    '' as currency,
    j.total_debit as total_debit,
    j.total_credit as total_credit,
    abs(j.total_debit - j.total_credit) as imbalance,
    'no currency: the group declares no reporting currency with a minor unit' as reason
from journals as j
where j.consolidation_group not in (select consolidation_group from units)
