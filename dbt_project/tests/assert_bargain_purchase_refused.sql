-- konsolidat#198 (design §1a, row J4): a submitted Business Combination whose group's policy is
-- `bargain_purchase = 'Refuse'` and whose price is below the fair value acquired (negative goodwill).
-- gold_business_combination_journal posts NOTHING for such a deal (IFRS 3.36 asks for a reassessment
-- of what was acquired and what was paid before any gain is booked), so the build must stop here and
-- name it: the group either corrects the Business Combination in konsol or changes its policy to
-- 'Recognise gain'. One row per refused deal: deal, group, entity, consideration, bargain amount.
--
-- How it is found: a deal of a 'Refuse' group with no journal lines at all. The journal refuses a
-- deal only for this reason; a deal it cannot measure (empty acquired-balances table and
-- net_assets_acquired = 0) also posts nothing and is named by assert_goodwill_calculated, and lands
-- here too under 'Refuse' (then bargain_purchase_gain is 0 and the row says so). The amount is the
-- header's Result figure as konsol computed it (group currency); the journal's own figure does not
-- exist for a deal it did not post. Fixture: dbt_project/test_fixtures/business_combination_bargain.refuse.sql.
select
    bc.name as business_combination,
    bc.consolidation_group,
    bc.acquired_entity,
    bc.total_consideration,
    if(bc.bargain_purchase_gain > 0, bc.bargain_purchase_gain, -least(bc.goodwill, 0.0)) as bargain_purchase_gain,
    if(bc.bargain_purchase_gain > 0 or bc.goodwill < 0, 'bargain purchase refused by policy', 'no journal posted: deal not measurable') as reason
from {{ source('epm_staging', 'business_combinations') }} as bc
inner join (
    select consolidation_group, any(bargain_purchase) as bargain_purchase
    from {{ source('epm_gold', 'consolidation_groups') }}
    where data_area_id = ''
    group by consolidation_group
) as gp
    on gp.consolidation_group = bc.consolidation_group
left join (
    select deal, count() as n_lines
    from {{ ref('gold_business_combination_journal') }}
    group by deal
) as j
    on j.deal = bc.name
where gp.bargain_purchase = 'Refuse'
  and coalesce(j.n_lines, 0) = 0
