-- konsolidat#198 row J11 (PR #203 review 7): layer 6 of gold_fully_consolidated_tb must carry
-- the deal journals at the account grain — exactly one row per (group, entity, year, period,
-- account, adjustment_type, journal_id) for adjustment_type 'acquisition',
-- 'goodwill_amortisation' and 'disposal'.
--
-- The journals themselves post several lines to one account in one period when the roles
-- differ: the acquisition journal's line (0) opening_balance and its equity_eliminated line on
-- the same equity account (history fixture ZZ3100: -687.5 and +687.5), the disposal journal's
-- derecognised and proceeds lines on the same cash account. gold_consolidated_ytd runs a
-- `rows between unbounded preceding and current row` window ordered by fiscal_period, so two
-- rows in one period give two running totals (-687.5, then 0) instead of one (0). Layer 6 SUMs
-- each journal branch to this grain, like the proration branch and layer 1 already do; a row
-- here means a branch passes journal lines through unsummed.
-- Fixture: dbt_project/test_fixtures/business_combination_history.sql
-- (`+gold_fully_consolidated_tb assert_journal_grain_unique assert_acquisition_journal_balances`).
select
    consolidation_group,
    data_area_id,
    fiscal_year,
    fiscal_period,
    main_account,
    adjustment_type,
    journal_id,
    count() as n_rows,
    sum(amount) as net_amount
from {{ ref('gold_fully_consolidated_tb') }}
where adjustment_type in ('acquisition', 'goodwill_amortisation', 'disposal')
group by
    consolidation_group,
    data_area_id,
    fiscal_year,
    fiscal_period,
    main_account,
    adjustment_type,
    journal_id
having count() > 1
