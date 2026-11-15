-- konsolidat#245 option D (Deepak Pai, 3 Oct 2026: a consolidation entry carries
-- the dimension values of whatever knows them; inherit where derivable). The NCI
-- attribution (layer 'nci_attribution', gold_nci_attribution_journal) is the
-- minority's share of the subsidiary's own P&L, and that P&L carries dimension
-- values, so its result legs are derivable per slice: in every slice the
-- retained-earnings line is minus (1 - ownership) x that slice's translated P&L
-- (year-end close rows excluded), and the NCI line is its opposite. The CTA leg
-- is a share of the entity's one CTA plug, which has no slice by arithmetic
-- (assert_sliceless_layers_carry_no_dimension), so it and the NCI line's CTA
-- part sit in the blank slice.
--
-- Read from the layer as gold_fully_consolidated_tb carries it, which is where a
-- dimension slice is reported. Two checks, one row per failing (group, entity,
-- period, slice):
--   1. the retained-earnings line of the slice equals the expected share;
--   2. the journal nets to zero within the slice (the NCI line follows the
--      result legs into their slices, not only the total).
-- assert_nci_attribution_equals_minority_result checks the entity-period
-- totals; this test checks how they are spread. Before this change every line
-- was blank, so a sliced P&L failed check 1.
-- Fixture: test_fixtures/assert_nci_attribution_carries_the_result_slices.sql.
with close_keys as (
    select distinct data_area_id, fiscal_year, fiscal_period, main_account
    from {{ ref('gold_trial_balance_by_partner') }}
    where is_year_end_close = 1
),

expected as (
    select
        eo.consolidation_group as consolidation_group,
        eo.data_area_id as data_area_id,
        eo.fiscal_year as fiscal_year,
        eo.fiscal_period as fiscal_period,
        {{ dim_select(prefix='ctb.', trailing=true) }}
        -(1.0 - eo.effective_ownership_pct) * sum(toFloat64(ctb.translated_amount)) as expected_re
    from {{ ref('gold_entity_ownership') }} as eo
    inner join {{ ref('gold_consolidated_trial_balance') }} as ctb
        on ctb.consolidation_group = eo.consolidation_group
        and ctb.data_area_id = eo.data_area_id
        and ctb.fiscal_year = eo.fiscal_year
        and ctb.fiscal_period = eo.fiscal_period
    where eo.consolidation_method = 'full'
      and eo.has_complete_chain = 1
      and eo.effective_ownership_pct < 1 - 0.000001
      and ctb.is_pnl = 1
      and (ctb.data_area_id, ctb.fiscal_year, ctb.fiscal_period, ctb.main_account)
          not in (select data_area_id, fiscal_year, fiscal_period, main_account from close_keys)
    group by eo.consolidation_group, eo.data_area_id, eo.fiscal_year, eo.fiscal_period,
             eo.effective_ownership_pct{{ dim_group_by(prefix='ctb.', leading=true) }}
),

{# Only entity-periods that got a journal: a missing journal is
   assert_nci_attribution_equals_minority_result's finding, not this test's. #}
layer as (
    select *
    from {{ ref('gold_fully_consolidated_tb') }}
    where adjustment_type = 'nci_attribution'
),

journaled as (
    select distinct consolidation_group, data_area_id, fiscal_year, fiscal_period
    from layer
),

re_accounts as (
    select distinct main_account_id
    from {{ ref('silver_main_accounts') }}
    where is_retained_earnings = 1
),

compared as (
    select e.consolidation_group as consolidation_group, e.data_area_id as data_area_id,
           e.fiscal_year as fiscal_year, e.fiscal_period as fiscal_period,
           {{ dim_select(prefix='e.', trailing=true) }}
           e.expected_re as expected_re, 0.0 as actual_re, 0.0 as slice_net
    from expected as e
    inner join journaled as jd
        on jd.consolidation_group = e.consolidation_group
        and jd.data_area_id = e.data_area_id
        and jd.fiscal_year = e.fiscal_year
        and jd.fiscal_period = e.fiscal_period
    union all
    select j.consolidation_group, j.data_area_id, j.fiscal_year, j.fiscal_period,
           {{ dim_select(prefix='j.', trailing=true) }}
           0.0,
           sumIf(toFloat64(j.amount), j.main_account in (select main_account_id from re_accounts)),
           sum(toFloat64(j.amount))
    from layer as j
    group by j.consolidation_group, j.data_area_id, j.fiscal_year, j.fiscal_period{{ dim_group_by(prefix='j.', leading=true) }}
)

select
    consolidation_group, data_area_id, fiscal_year, fiscal_period,
    {{ dim_select(trailing=true) }}
    sum(expected_re) as expected_re_total,
    sum(actual_re) as actual_re_total,
    sum(slice_net) as slice_net_total
from compared
group by consolidation_group, data_area_id, fiscal_year, fiscal_period{{ dim_group_by(leading=true) }}
having abs(sum(expected_re) - sum(actual_re)) > 0.01
    or abs(sum(slice_net)) > 0.01
