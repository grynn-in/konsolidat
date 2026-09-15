-- konsolidat#198 (design §6): every goodwill amortisation journal (GWA-…) sums to zero in
-- each of its periods: the expense debit and the goodwill credit of one instalment are each
-- other's counterpart (design §1, goodwill_treatment = 'Amortise'). A row here is a model
-- bug, not a data problem.
--
-- One test per journal model (row J5cb), each ref-ing only its own model, so that
-- `+gold_goodwill_amortisation_journal assert_goodwill_amortisation_journal_balances` is
-- selectable on its own. Siblings: assert_acquisition_journal_balances,
-- assert_disposal_journal_balances. Fixtures: dbt_project/test_fixtures/goodwill_amortisation.sql,
-- goodwill_amortisation.disposal.sql.
select
    journal_id,
    consolidation_group,
    fiscal_year,
    fiscal_period,
    count() as journal_lines,
    sum(adjustment_amount) as net_amount
from {{ ref('gold_goodwill_amortisation_journal') }}
group by journal_id, consolidation_group, fiscal_year, fiscal_period
having abs(sum(adjustment_amount)) > 0.01
