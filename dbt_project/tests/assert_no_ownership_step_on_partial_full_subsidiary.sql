{{ config(severity='error') }}
{#
    konsol#117 pair 2 review, finding 3 (konsolidat#318, IFRS 10.23 / B96).
    A change in the parent's ownership interest in a subsidiary it keeps
    controlling is an equity transaction between owners: the NCI is re-measured
    to the new share of the subsidiary's net assets and the difference goes to
    the parent's equity. The attribution layer (gold_nci_attribution_journal)
    attributes each period's result and CTA at THAT period's share, and the
    deal journals handle acquisitions and disposals; nothing rebalances the NCI
    balance when the share steps with no deal (an ownership period that changes
    its percentage, a capital increase the group does not follow). The NCI
    balance keeps the old share's net assets.

    One row per (group, full-method entity) and pair of consecutive ownership
    periods (ordered by FY, period within the group) whose
    effective_ownership_pct differs while it is below 100% on either side, and
    the later period carries no acquisition or disposal journal line for the
    entity (gold_business_combination_journal / gold_business_disposal_journal,
    which post their own NCI). A step to or from 0 is a deal and is not in
    gold_entity_ownership at all.

    konsol#117 pair 3 (row K3): a joint operation (consolidation_method
    proportional, IFRS 11) is refused too. Layer 1 carries it at the
    operator's share, and the CTB is movement-grained: movements before the
    step sit at the old share, later ones at the new one, so no balance sheet
    is at either share, and nothing restates the earlier movements. The
    problem sentence names the method. The name keeps "full_subsidiary" so the
    test stays one test.

    konsol#117 pair 3 review, finding C: a change of METHOD at the same share (full 50% -> proportional 50%, or the
    reverse) is a step too: layer 1 carries the earlier movements at 100% with NCI and the later ones at the share
    with none. The trigger is a changed share OR a changed method (prev_method '' is the first row). And a deal line
    no longer exempts a step whose method is or was proportional: the deal journals handle controlled-subsidiary
    NCI only, nothing restates a joint operation's earlier movements.

    Fixtures: test_fixtures/assert_no_ownership_step_on_partial_full_subsidiary
    (.must_flag.sql: 70% then 80%; nci_attribution_journal.sql is the passing
    case, an unchanged share).
#}
with owned as (
    select
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        consolidation_method,
        toFloat64(effective_ownership_pct) as pct,
        lagInFrame(fiscal_year, 1, 0) over w as prev_year,
        lagInFrame(fiscal_period, 1, 0) over w as prev_period,
        lagInFrame(toFloat64(effective_ownership_pct), 1, 0) over w as prev_pct,
        lagInFrame(consolidation_method, 1, '') over w as prev_method
    from {{ ref('gold_entity_ownership') }}
    where consolidation_method in ('full', 'proportional')
      and has_complete_chain = 1
    window w as (
        partition by consolidation_group, data_area_id
        order by fiscal_year, fiscal_period
        rows between unbounded preceding and unbounded following
    )
),

deal_lines as (
    select distinct consolidation_group, data_area_id, fiscal_year, fiscal_period
    from {{ ref('gold_business_combination_journal') }}
    union distinct
    select distinct consolidation_group, data_area_id, fiscal_year, fiscal_period
    from {{ ref('gold_business_disposal_journal') }}
),

-- GAP periods between a row and the previous row of its entity (konsol#117 pair 3 review, findings K, R, S). A step needs
-- the entity in the group throughout; after a real gap it left and re-enters by a deal, which is not a step. gold_entity_ownership
-- has rows only for periods with a trial balance, so absent rows prove nothing. A Regular fiscal period strictly between the two
-- rows (Opening and Closing periods are not periods of activity) is a gap only if NO ownership period of the entity in the
-- group (any owner, ownership_pct > 0) covers its start_date.
gap_candidates as (
    select
        o.consolidation_group as consolidation_group,
        o.data_area_id as data_area_id,
        o.fiscal_year as fiscal_year,
        o.fiscal_period as fiscal_period,
        fp.fiscal_year as gap_year,
        fp.fiscal_period as gap_period,
        fp.start_date as gap_start
    from owned as o
    cross join {{ source('epm_staging', 'fiscal_periods') }} as fp
    where o.prev_year != 0
      and fp.period_type = 'Regular'
      and (toUInt32(fp.fiscal_year), toUInt32(fp.fiscal_period)) > (toUInt32(o.prev_year), toUInt32(o.prev_period))
      and (toUInt32(fp.fiscal_year), toUInt32(fp.fiscal_period)) < (toUInt32(o.fiscal_year), toUInt32(o.fiscal_period))
),

gap_covered as (
    select distinct
        g.consolidation_group as consolidation_group,
        g.data_area_id as data_area_id,
        g.gap_year as gap_year,
        g.gap_period as gap_period
    from gap_candidates as g
    cross join {{ source('epm_staging', 'ownership_periods') }} as op
    where op.consolidation_group = g.consolidation_group
      and op.data_area_id = g.data_area_id
      and op.ownership_pct > 0
      and op.effective_date <= g.gap_start
      and op.end_date >= g.gap_start
),

gap_periods as (
    select
        g.consolidation_group as consolidation_group,
        g.data_area_id as data_area_id,
        g.fiscal_year as fiscal_year,
        g.fiscal_period as fiscal_period,
        count() as n_between
    from gap_candidates as g
    where (g.consolidation_group, g.data_area_id, g.gap_year, g.gap_period)
        not in (select consolidation_group, data_area_id, gap_year, gap_period from gap_covered)
    group by g.consolidation_group, g.data_area_id, g.fiscal_year, g.fiscal_period
)

select
    o.consolidation_group as consolidation_group,
    o.data_area_id as data_area_id,
    o.prev_year as from_fiscal_year,
    o.prev_period as from_fiscal_period,
    o.fiscal_year as to_fiscal_year,
    o.fiscal_period as to_fiscal_period,
    o.prev_pct as old_pct,
    o.pct as new_pct,
    o.consolidation_method as consolidation_method,
    o.prev_method as prev_method,
    concat('entity ', o.data_area_id, ' in group ', o.consolidation_group, ' steps from ',
           toString(round(o.prev_pct * 100, 4)), '% (FY', toString(o.prev_year), ' P', toString(o.prev_period),
           ') to ', toString(round(o.pct * 100, 4)), '% (FY', toString(o.fiscal_year), ' P', toString(o.fiscal_period),
           '): ',
           if(o.prev_method != o.consolidation_method,
              concat('a change of consolidation method from ', o.prev_method, ' to ', o.consolidation_method, ' at the same or a different share is not implemented: the CTB is movement-grained, so earlier movements stay under ', o.prev_method, ' and later ones follow ', o.consolidation_method),
           if(o.consolidation_method = 'proportional',
              'an ownership step on a joint operation (consolidation_method proportional) is not implemented: the CTB is movement-grained, so earlier movements stay at the old share and later ones take the new one (IFRS 11.20)',
              'an ownership step on a controlled subsidiary is not rebalanced against NCI yet (IFRS 10.23/B96, konsolidat#318); the NCI balance keeps the old share''s net assets'))) as problem
from owned as o
left join gap_periods as b
    on b.consolidation_group = o.consolidation_group
    and b.data_area_id = o.data_area_id
    and b.fiscal_year = o.fiscal_year
    and b.fiscal_period = o.fiscal_period
left join deal_lines as d
    on d.consolidation_group = o.consolidation_group
    and d.data_area_id = o.data_area_id
    and d.fiscal_year = o.fiscal_year
    and d.fiscal_period = o.fiscal_period
where o.prev_year != 0
  and coalesce(b.n_between, 0) = 0
  and (
        (abs(o.pct - o.prev_pct) > 0.000001 and (o.pct < 1 - 0.000001 or o.prev_pct < 1 - 0.000001))
        or (o.prev_method != '' and o.consolidation_method != o.prev_method)
      )
  and (d.data_area_id = '' or o.consolidation_method = 'proportional' or o.prev_method = 'proportional')
