-- konsolidat#213 (row D4): the goodwill the acquisition journal posts must equal the goodwill konsol
-- computed on the submitted Business Combination. Both are the same deal's figure in group currency
-- (_staging__sources.yml: "the header carries the deal and konsol's Result figures in group currency"),
-- and until this test nothing said so.
--
-- Why it matters: konsol measures net assets from the account TYPE (business_combination.py:
-- account_type == "Equity"), while gold_business_combination_journal measures them from
-- silver_main_accounts.is_equity. While is_equity meant "translated at historical rate" the two could
-- disagree on any account a chart declares historical without typing as Equity — and would have, silently,
-- on the first submitted deal: the journal would have eliminated those balances as pre-acquisition equity
-- while the header's goodwill came from the account type. is_equity is now the account type (row D1), so the
-- two meanings are one; this test is what keeps them that way.
--
-- The journal's figure is the deal's goodwill_raw = consideration + capitalised costs + NCI −
-- (net assets + FVA): the `goodwill` line when it is positive, the `bargain_gain` line when it is negative
-- (exactly one of the two posts, design §4 lines 3 and 3b). The header's is `goodwill`, or
-- −`bargain_purchase_gain` when konsol booked the bargain in that column instead.
--
-- Only deals the journal actually posted are compared (INNER JOIN on its lines): a deal it refuses
-- (bargain under 'Refuse') or cannot measure (no acquired balance sheet) posts no line at all and is named
-- by assert_bargain_purchase_refused / assert_goodwill_calculated, not here.
-- One row per deal that disagrees, with both numbers.
-- Fixtures: dbt_project/test_fixtures/business_combination_100pct.sql (PASS) and
-- dbt_project/test_fixtures/assert_deal_goodwill_matches_header.must_flag.sql (the same rows with the
-- header's goodwill moved 500 off the journal's; must FAIL with 1 result).
with header as (
    select
        name as deal,
        consolidation_group,
        acquired_entity,
        if(abs(goodwill) > {{ materiality_floor() }}, goodwill, -bargain_purchase_gain) as header_goodwill
    from {{ source('epm_staging', 'business_combinations') }}
),

journal as (
    select
        deal,
        sumIf(adjustment_amount, account_role in ('goodwill', 'bargain_gain')) as journal_goodwill
    from {{ ref('gold_business_combination_journal') }}
    group by deal
)

select
    h.deal as business_combination,
    h.consolidation_group as consolidation_group,
    h.acquired_entity as acquired_entity,
    h.header_goodwill as header_goodwill,
    j.journal_goodwill as journal_goodwill,
    j.journal_goodwill - h.header_goodwill as difference
from header as h
inner join journal as j
    on j.deal = h.deal
where abs(j.journal_goodwill - h.header_goodwill) > {{ materiality_floor() }}
order by business_combination
