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
        toFloat64(effective_ownership_pct) as pct,
        lagInFrame(fiscal_year, 1, 0) over w as prev_year,
        lagInFrame(fiscal_period, 1, 0) over w as prev_period,
        lagInFrame(toFloat64(effective_ownership_pct), 1, 0) over w as prev_pct
    from {{ ref('gold_entity_ownership') }}
    where consolidation_method = 'full'
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
    concat('entity ', o.data_area_id, ' in group ', o.consolidation_group, ' steps from ',
           toString(round(o.prev_pct * 100, 4)), '% (FY', toString(o.prev_year), ' P', toString(o.prev_period),
           ') to ', toString(round(o.pct * 100, 4)), '% (FY', toString(o.fiscal_year), ' P', toString(o.fiscal_period),
           '): an ownership step on a controlled subsidiary is not rebalanced against NCI yet ',
           '(IFRS 10.23/B96, konsolidat#318); the NCI balance keeps the old share''s net assets') as problem
from owned as o
left join deal_lines as d
    on d.consolidation_group = o.consolidation_group
    and d.data_area_id = o.data_area_id
    and d.fiscal_year = o.fiscal_year
    and d.fiscal_period = o.fiscal_period
where o.prev_year != 0
  and abs(o.pct - o.prev_pct) > 0.000001
  and (o.pct < 1 - 0.000001 or o.prev_pct < 1 - 0.000001)
  and d.data_area_id = ''
