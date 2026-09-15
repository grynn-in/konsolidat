{{ config(severity='warn') }}
-- konsolidat#198 (design §2/§3, row J10; PR #203 review 5): a submitted Business Combination whose acquired
-- balance sheet (epm_staging.business_combination_acquired_balances, konsol's table: entity currency, Dr
-- positive, Cr negative) does not agree with itself. Two problems, one row per deal and problem:
--   'acquired balance sheet does not sum to zero'          sum(book_amount) over the deal's rows, abs > materiality_floor():
--                                                          a balance sheet balances; one that does not is
--                                                          missing a line or carries a mistyped amount
--   'main_account is not a posting account of the chart'   a row whose account is not a Published posting leaf
--                                                          of silver_main_accounts (idx named in detail)
-- Both are silent in gold_business_combination_journal: it eliminates the rows the chart flags is_equity (an
-- unknown account is not equity, so its row is simply ignored) and measures the net assets as -(the equity
-- eliminated), so the journal still balances, with the goodwill measured against an equity that does not match
-- the assets and liabilities konsol recorded. Warn severity: the accountant should complete the Business
-- Combination in konsol (design §2: the acquisition-date balance sheet is the document's), the build goes on.
-- A deal with no acquired-balance rows is not named here (it is measured another way, design §3).
-- Fixture: dbt_project/test_fixtures/assert_acquired_balances_complete.must_flag.sql.
with balances as (
    select
        ab.parent as deal,
        toUInt16(ab.idx) as idx,
        ab.main_account as main_account,
        toFloat64(ab.book_amount) as book_amount
    from {{ source('epm_staging', 'business_combination_acquired_balances') }} as ab
    inner join {{ source('epm_staging', 'business_combinations') }} as bc
        on bc.name = ab.parent
),

chart as (
    select main_account_id
    from {{ ref('silver_main_accounts') }}
    where main_account_id != ''
    group by main_account_id
),

unbalanced as (
    select
        deal,
        'acquired balance sheet does not sum to zero' as problem,
        concat('sum(book_amount) = ', toString(round(sum(book_amount), 2)), ' over ', toString(count()), ' rows') as detail
    from balances
    group by deal
    having abs(sum(book_amount)) > {{ materiality_floor() }}
),

unknown_account as (
    select
        b.deal as deal,
        'main_account is not a posting account of the chart' as problem,
        concat(b.main_account, ' (idx ', toString(b.idx), ')') as detail
    from balances as b
    left join chart as ch
        on ch.main_account_id = b.main_account
    where coalesce(ch.main_account_id, '') = ''
)

select deal as business_combination, problem, detail
from (
    select deal, problem, detail from unbalanced
    union all
    select deal, problem, detail from unknown_account
)
order by business_combination, problem, detail
