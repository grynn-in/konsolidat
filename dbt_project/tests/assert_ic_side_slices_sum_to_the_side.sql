-- konsolidat#245 option D / layer 2 option C (Deepak Pai, 6 Oct 2026).
--
-- gold_ic_side_slices must be gold_ic_reconciliation's `sides` CTE split by the
-- declared dimensions and NOTHING ELSE: same source, same filters, same join.
-- Every slice of a side must therefore sum to exactly that side's movement.
--
-- That identity is the whole reason the elimination split is exact rather than
-- an allocation. If it breaks — a different filter, a join that fans out, a
-- dimension column that is NULL rather than '' — the split silently
-- redistributes an elimination across slices whose amounts no longer add up to
-- what was eliminated, and every row still balances. This test is the guard
-- against that, so it is error severity, not warn.
--
-- One row per side whose slices do not reconcile, with both figures.
-- Compared with materiality_floor(), not exact equality: both sides are
-- Float64 sums and a slice split changes the summation order.
with per_side as (
    select
        consolidation_group,
        fiscal_year,
        fiscal_period,
        entity,
        partner,
        account,
        sum(mov_local) as sliced_local,
        sum(mov_translated) as sliced_translated,
        sum(mov_group) as sliced_group
    from {{ ref('gold_ic_side_slices') }}
    group by consolidation_group, fiscal_year, fiscal_period, entity, partner, account
),

reconciliation_side as (
    select
        ctb.consolidation_group as consolidation_group,
        ctb.fiscal_year as fiscal_year,
        ctb.fiscal_period as fiscal_period,
        ctb.data_area_id as entity,
        ctb.partner_data_area_id as partner,
        ctb.main_account as account,
        ifNull(toFloat64(sum(ctb.local_amount)), 0) as side_local,
        ifNull(toFloat64(sum(ctb.translated_amount)), 0) as side_translated,
        ifNull(toFloat64(sum(ctb.group_amount)), 0) as side_group
    from {{ ref('gold_consolidated_trial_balance') }} as ctb
    inner join ({{ ic_account_map() }}) as ica
        on ctb.main_account = ica.account
    where ctb.partner_data_area_id != ''
      and ctb.partner_data_area_id != ctb.data_area_id
    group by
        ctb.consolidation_group,
        ctb.fiscal_year,
        ctb.fiscal_period,
        ctb.data_area_id,
        ctb.partner_data_area_id,
        ctb.main_account
)

select
    r.consolidation_group,
    r.fiscal_year,
    r.fiscal_period,
    r.entity,
    r.partner,
    r.account,
    r.side_group,
    s.sliced_group,
    r.side_group - s.sliced_group as difference
{# PR #260 review F4: a FULL join, not an inner one. With an inner join a side
   MISSING ENTIRELY from gold_ic_side_slices produced no row and the test
   passed — and a filter that drops whole sides is exactly what sends layer 2
   down its join-miss path. s.entity = '' now means "no slice rows at all",
   which under join_use_nulls=0 is how an unmatched side reads.

   KNOWN LIMITATION (re-review finding 3): reconciliation_side below is a hand
   copy of gold_ic_side_slices' own query — same source, same ic_account_map()
   join, same two partner filters — so on today's code neither side of this
   join can hold a key the other lacks, and no branch here can fire. It guards
   against the model DRIFTING from the reconciliation later, which is worth
   having, and it is not evidence about layer 2's output. #}
from reconciliation_side as r
full outer join per_side as s
    on r.consolidation_group = s.consolidation_group
    and r.fiscal_year = s.fiscal_year
    and r.fiscal_period = s.fiscal_period
    and r.entity = s.entity
    and r.partner = s.partner
    and r.account = s.account
where abs(r.side_group - s.sliced_group) > {{ materiality_floor() }}
   or abs(r.side_local - s.sliced_local) > {{ materiality_floor() }}
   or abs(r.side_translated - s.sliced_translated) > {{ materiality_floor() }}
   {# a side on one side of the join only: dropped from the slices, or invented
      by them. Either way the apportionment base is wrong. #}
   or r.entity = ''
   or s.entity = ''
