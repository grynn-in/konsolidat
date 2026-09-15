-- PRD-11 test: every submitted acquisition with a price must have had its goodwill calculated.
--
-- konsolidat#198 (row J2b): rewritten to read epm_staging.business_combinations instead of
-- ownership_periods, and gold_business_combination_journal instead of gold_acquisition_adjustments.
-- Why: since konsolidat#198 the deal lives on the submitted Business Combination document (submit =
-- approval), and gold_business_combination_journal posts the balanced acquisition journal from it;
-- gold_acquisition_adjustments no longer posts goodwill rows. The Ownership Period only carries the
-- effective share and the consolidation window, so a priced Ownership Period is no longer a deal the
-- warehouse must account for (the stack's deals are still Drafts there: nothing submitted, nothing
-- owed). Coupling this test to ownership_periods would fail every acquisition period for no reason.
--
-- Flags a submitted deal with total_consideration > 0 whose journal has neither a `goodwill` nor a
-- `bargain_gain` line (from row J4 a bargain purchase books the gain instead of goodwill). The usual
-- cause: no measurement basis (empty acquired-balances table and net_assets_acquired = 0), so the
-- journal posted nothing for the deal. A deal whose consideration equals fair-value net assets to the
-- cent has neither line either and is named here too; that coincidence is worth a look.
select
    bc.name as business_combination,
    bc.consolidation_group,
    bc.acquired_entity,
    bc.total_consideration
from {{ source('epm_staging', 'business_combinations') }} as bc
left join (
    select deal, count() as n_lines
    from {{ ref('gold_business_combination_journal') }}
    where account_role in ('goodwill', 'bargain_gain')
    group by deal
) as j
    on j.deal = bc.name
where bc.total_consideration > 0
  and coalesce(j.n_lines, 0) = 0
