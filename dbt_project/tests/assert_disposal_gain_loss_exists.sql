-- PRD-12 test: every submitted disposal must have produced a gain or loss.
--
-- konsolidat#198 (row J6b): rewritten to read epm_staging.business_disposals instead of
-- ownership_periods, and gold_business_disposal_journal instead of gold_disposal_adjustments.
-- Why: since konsolidat#198 the disposal lives on the submitted Business Disposal document (submit =
-- approval), and gold_business_disposal_journal posts the balanced disposal journal from it;
-- gold_disposal_adjustments, which posted the one-sided 'disposal_gain_loss' row this test used to look
-- for, is gone. The Ownership Period only carries the effective share and the consolidation window, so
-- an Ownership Period flagged is_disposal is no longer a deal the warehouse must account for (on the
-- stack the deals are still Drafts: nothing submitted, nothing owed). Coupling this test to
-- ownership_periods would flag every disposal window for no reason.
--
-- Flags a submitted disposal whose journal has no `gain_loss` line. Two causes, both worth the
-- accountant's eye:
--   * a retained interest (retained_interest_pct > 0): the journal posts only full disposals; the
--     remeasurement of the interest kept is out of scope (design §5, §7) and must be booked as a
--     manual topside, so the disposal is NAMED here rather than posted wrong or silently skipped;
--   * no posting at all: the group has no root row in consolidation_groups, or the disposal date is
--     outside the declared calendar (row J7's guard names the missing declaration itself).
-- A disposal whose proceeds equal the carrying amount to the cent has no gain_loss line either and
-- is named here too; that coincidence is worth a look.
select
    bd.name as business_disposal,
    bd.consolidation_group,
    bd.disposed_entity,
    bd.disposal_date,
    bd.retained_interest_pct,
    bd.total_proceeds
from {{ source('epm_staging', 'business_disposals') }} as bd
left join (
    select deal, count() as n_lines
    from {{ ref('gold_business_disposal_journal') }}
    where account_role = 'gain_loss'
    group by deal
) as j
    on j.deal = bd.name
where coalesce(j.n_lines, 0) = 0
