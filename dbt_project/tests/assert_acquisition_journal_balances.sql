-- konsolidat#198 (design §6): every acquisition journal (ACQ-…) the warehouse posts from a
-- submitted Business Combination sums to zero in its period. The journal is balanced by
-- construction (design §4: goodwill or the bargain gain is the counterpart of every other
-- line), so a row here is a model bug, not a data problem: one-sided rows were exactly what
-- made assert_end_to_end_bs_balances (PRD-22) fail on every acquisition period before this.
--
-- One test per journal model (row J5cb), each ref-ing only its own model, so that
-- `+gold_business_combination_journal assert_acquisition_journal_balances` is selectable on
-- its own and a fixture that CREATEs only the acquisition tables builds it. Siblings:
-- assert_goodwill_amortisation_journal_balances, assert_disposal_journal_balances.
-- Fixtures: dbt_project/test_fixtures/business_combination_100pct.sql, business_combination_bargain.sql.
select
    journal_id,
    consolidation_group,
    fiscal_year,
    fiscal_period,
    count() as journal_lines,
    sum(adjustment_amount) as net_amount
from {{ ref('gold_business_combination_journal') }}
group by journal_id, consolidation_group, fiscal_year, fiscal_period
having abs(sum(adjustment_amount)) > 0.01
