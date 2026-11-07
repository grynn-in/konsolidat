-- PRD-14: every equity-method journal (EQ_<group>_<entity>_<year>_P<period>) the warehouse posts
-- sums to zero in its period: the EQ_INCOME line and the EQ_INVEST line are the two sides of one
-- entry (Cr share of profit, Dr investment), so a row here is a model bug, not a data problem.
-- Found 7 Nov 2026 building the aquila-bike example: gold_equity_method_associates put the SAME
-- signed figure on both lines, so a profit of X posted -X twice (net -2X) into layer 5 of
-- gold_fully_consolidated_tb, and assert_end_to_end_bs_balances (PRD-22) failed for any group
-- with an associate in every period the associate had a result.
--
-- Same pattern as the deal-journal tests (assert_acquisition_journal_balances and siblings): one
-- test, ref-ing only its own model, so `gold_equity_method_associates assert_equity_method_journal_balances`
-- is selectable on its own. Fixture: dbt_project/test_fixtures/assert_equity_method_journal_balances.sql
-- (SEK associate at 30% in a EUR group; a 1,000 SEK profit at a 0.09 Average rate is
-- EQ_INCOME -27.00 / EQ_INVEST +27.00).
{{ config(severity='error') }}
select
    journal_id,
    consolidation_group,
    data_area_id,
    fiscal_year,
    fiscal_period,
    count() as journal_lines,
    sum(amount) as net_amount
from {{ ref('gold_equity_method_associates') }}
group by journal_id, consolidation_group, data_area_id, fiscal_year, fiscal_period
having abs(sum(amount)) > 0.01
