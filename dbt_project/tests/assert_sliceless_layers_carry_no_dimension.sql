-- konsolidat#245 option D, decided by Deepak Pai on 3 October 2026: a
-- consolidation entry carries the dimension values of whatever knows them. The
-- deal-journal layers of gold_fully_consolidated_tb (pnl_proration excepted, see below) — acquisition,
-- business combination, goodwill amortisation and disposal — know none, with one exception: disposal line
-- 105 (account_role 'post_disposal_pnl'), see below. Their
-- inputs are the Business Combination and Business Disposal documents, which
-- carry no dimension fields and have no slice to inherit from. The CTA is
-- blank for a different and stronger reason: it is ONE PLUG per entity and
-- period (-sum(group_amount) across every account), the residual that makes
-- the entity's translated balance sheet balance, so a per-dimension CTA would
-- be an arbitrary allocation rather than a translation difference. All five
-- are blank BY DECISION and nothing should be invented for them.
--
-- "Blank by decision" is worth asserting, because it is indistinguishable in
-- the data from "blank because somebody forgot" — which is what the other eight
-- layers were before this issue. If a deal layer ever starts carrying a value,
-- either someone gave those documents a dimension (then this test is the place
-- to record the new decision) or a layer is reading a slice it cannot know.
--
-- The NCI attribution ('nci_attribution', gold_nci_attribution_journal) is half
-- covered. Its result legs inherit the slices of the entity's P&L (option D:
-- derivable, so inherited; assert_nci_attribution_carries_the_result_slices).
-- Its 'CTA' line is a share of the same entity-level CTA plug as the 'cta'
-- layer, so it is blank by the same arithmetic and is asserted here by account.
-- The CTA part of its NCI line is blank too, but shares the NCI account with
-- the sliced result part, so it cannot be told apart here; the slice test's
-- every-slice-nets-to-zero check covers it.
--
-- NOT COVERED HERE, deliberately: 'ic_elimination' and 'ic_elimination_nci'.
-- Layer 2 legs posted to a non-IC account (the NCI line, a group's
-- IC-difference account) never match a slice row and correctly land on a blank
-- slice, so blankness is legal there and this test would be wrong to forbid it.
-- PR #260 review F5 is right that such a row is then indistinguishable from
-- one blank because the side booked no value; distinguishing them needs a
-- reason column on the layer, which is not in this change.
-- assert_ic_elimination_slices_sum_to_the_leg is what guards layer 2 instead.
--
-- Disposal line 105 (post_disposal_pnl) is exempt: konsolidat#245 Q2 A, decided by Deepak Pai on
-- 21 Nov 2026, extends "inherit where derivable" to it. It is the entity's P&L by account times the removed
-- fraction, the derivation pnl_proration slices, so it carries the slices of the P&L it removes
-- (assert_post_disposal_pnl_carries_its_slices). Rejected: B, keep it blank, which overstated segment P&L by
-- the post-disposal P&L. Because gold_fully_consolidated_tb sums the journal's lines to the account grain and
-- drops account_role, the disposal layer is judged here on gold_business_disposal_journal itself, by role:
-- every line except 'post_disposal_pnl' must stay blank.
--
-- Equity method stays blank and asserted: konsolidat#245 Q3 A, decided by Deepak Pai on 21 Nov 2026 (it
-- had been settled by Claude on 6 Oct 2026 under his instruction). IAS 28 presents the result as one line,
-- and the associate's dimensions are not the group's. Rejected: B, inherit the associate's slices.
--
-- One row per offending layer and dimension. Error severity: a value here is
-- not a data-quality warning, it is a layer claiming knowledge it does not have.
{% set dims = var('dimensions') %}
{% if dims | length == 0 %}
select 1 as adjustment_type where 0
{% else %}
select
    adjustment_type,
    '{{ dims | map(attribute="name") | join(", ") }}' as checked_dimensions,
    count() as rows_carrying_a_value
from {{ ref('gold_fully_consolidated_tb') }}
-- The three values the deal journals emit, read from them rather than guessed.
-- 'pnl_proration' (gold_acquisition_adjustments) is NOT here: konsolidat#345
-- made that layer real, it carries the dimension slice of the P&L it prorates.
-- gold_business_combination_journal 'acquisition', gold_goodwill_amortisation_journal 'goodwill_amortisation',
-- 'disposal' (gold_business_disposal_journal) is judged by account_role in the second branch below.
where (adjustment_type in (
        'acquisition', 'goodwill_amortisation',
        -- the CTA, blank by arithmetic: an entity-level residual has no slice
        'cta',
        -- and equity method, blank by decision (konsolidat#245 Q3 A, Deepak
        -- Pai, 21 Nov 2026): the investor's one-line pickup does not carry
        -- the associate's management dimensions
        'equity_method')
       -- the NCI attribution's CTA leg, blank by the same arithmetic as 'cta'
       or (adjustment_type = 'nci_attribution' and main_account = 'CTA'))
  and (
    {%- for d in dims %}
    {{ d.name }} != ''{{ ' or' if not loop.last }}
    {%- endfor %}
  )
group by adjustment_type

union all

-- the disposal journal, every line but line 105 (Q2 A)
select
    concat(adjustment_type, ' (', account_role, ')') as adjustment_type,
    '{{ dims | map(attribute="name") | join(", ") }}' as checked_dimensions,
    count() as rows_carrying_a_value
from {{ ref('gold_business_disposal_journal') }}
where account_role != 'post_disposal_pnl'
  and (
    {%- for d in dims %}
    {{ d.name }} != ''{{ ' or' if not loop.last }}
    {%- endfor %}
  )
group by adjustment_type, account_role
{% endif %}
