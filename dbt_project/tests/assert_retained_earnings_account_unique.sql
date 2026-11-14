-- konsolidat#316 (option A, prerequisite): the journal layers close their P&L into ONE retained-earnings
-- account, found by the macro `retained_earnings_account()`: the single chart account with
-- is_retained_earnings = 1. With none flagged there is nowhere to close to; with two or more, any
-- choice (lowest code, anyIf) silently decides policy for the customer. Either way the journal-layer
-- close must not guess, so a consolidation group that carries journal-layer rows in
-- gold_fully_consolidated_tb (adjustment_type other than 'entity') while the flagged count is not
-- exactly 1 is an ERROR here, naming the group and the count. Fix: flag exactly one account.
-- Fixtures: dbt_project/test_fixtures/assert_retained_earnings_account_unique.one_account.sql (pass) and
-- assert_retained_earnings_account_unique.must_flag.sql (two flagged, one topside P&L row: flag 1).
{{ config(severity='error') }}

select
    f.consolidation_group as consolidation_group,
    max(re.re_count) as retained_earnings_flagged,
    count() as journal_rows
from {{ ref('gold_fully_consolidated_tb') }} as f
cross join {{ retained_earnings_account() }} as re
where f.adjustment_type != 'entity'
group by f.consolidation_group
having max(re.re_count) != 1
