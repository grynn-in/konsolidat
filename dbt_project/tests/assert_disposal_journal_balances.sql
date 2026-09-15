-- konsolidat#198 (design §6): every disposal journal (DSP-…) the warehouse posts from a
-- submitted Business Disposal sums to zero in its period. The journal is balanced by
-- construction (design §5: the gain/loss line is the counterpart of every other line), so a
-- row here is a model bug, not a data problem.
--
-- One test per journal model (row J5cb), each ref-ing only its own model, so that
-- `+gold_business_disposal_journal assert_disposal_journal_balances` is selectable on its
-- own. Siblings: assert_acquisition_journal_balances,
-- assert_goodwill_amortisation_journal_balances. Fixture:
-- dbt_project/test_fixtures/business_disposal.sql.
select
    journal_id,
    consolidation_group,
    fiscal_year,
    fiscal_period,
    count() as journal_lines,
    sum(adjustment_amount) as net_amount
from {{ ref('gold_business_disposal_journal') }}
group by journal_id, consolidation_group, fiscal_year, fiscal_period
having abs(sum(adjustment_amount)) > 0.01
