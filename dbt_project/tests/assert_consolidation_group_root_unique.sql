-- konsolidat#198 (design §1, row J10; PR #203 review 6): a consolidation group with more than one root row in
-- epm_gold.consolidation_groups (data_area_id = ''). The root row is where konsol syncs the group's reporting
-- currency, the deal policy and the deal accounts; the three deal journals (gold_business_combination_journal,
-- gold_goodwill_amortisation_journal, gold_business_disposal_journal) read it through their group_policy CTE.
-- Since row J10 that CTE aggregates the root row with any() per column, so a duplicate can no longer double
-- every line of every journal (the failure this test was written against: 10 acquisition lines instead of 5,
-- still summing to 0, so no balance test saw it), but any() picks one of the rows arbitrarily: if the two
-- disagree, the policy the journals apply is undefined. Error severity: the build stops and names the group.
-- Fixture: dbt_project/test_fixtures/assert_consolidation_group_root_unique.must_flag.sql.
select
    consolidation_group,
    count() as n_root_rows,
    arrayStringConcat(groupUniqArray(reporting_currency), ' | ') as reporting_currencies,
    arrayStringConcat(groupUniqArray(goodwill_account), ' | ') as goodwill_accounts
from {{ source('epm_gold', 'consolidation_groups') }}
where data_area_id = ''
group by consolidation_group
having count() > 1
order by consolidation_group
