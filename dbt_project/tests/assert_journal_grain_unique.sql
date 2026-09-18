-- konsolidat#198 row J11 (PR #203 review 7) + row J13 (second review 2): layer 6 of
-- gold_fully_consolidated_tb must carry the deal journals at the grain gold_consolidated_ytd
-- windows over — exactly one row per period within the YTD window's PARTITION BY
-- (consolidation_group, data_area_id, fiscal_year, main_account, adjustment_type, the dimension
-- columns) for adjustment_type 'acquisition', 'goodwill_amortisation' and 'disposal'.
--
-- The journals themselves post several lines to one account in one period when the roles
-- differ: the acquisition journal's line (0) opening_balance and its equity_eliminated line on
-- the same equity account (history fixture ZZ3100: -687.5 and +687.5), the disposal journal's
-- derecognised and proceeds lines on the same cash account. gold_consolidated_ytd runs a
-- `rows between unbounded preceding and current row` window ordered by fiscal_period, so two
-- rows in one period give two running totals (-687.5, then 0) instead of one (0). Layer 6 SUMs
-- each journal branch to this grain, like the proration branch and layer 1 already do; a row
-- here means a branch passes journal lines through unsummed.
--
-- Row J13: journal_id is NOT part of the key. The YTD window does not partition by it, so two
-- journals of one entity posting to one account in one period (a second deal, or an amortisation
-- instalment next to a disposal in the same period) would again be two rows under one running
-- total; layer 6 therefore groups without journal_id (emitting any(journal_id)) and this test
-- keys on exactly the window's partition columns plus fiscal_period. The journals seen so far
-- are reported as journal_ids for the reader.
-- Fixtures: dbt_project/test_fixtures/business_combination_history.sql and business_disposal.sql
-- (`+gold_fully_consolidated_tb assert_journal_grain_unique assert_acquisition_journal_balances`).
select
    consolidation_group,
    data_area_id,
    fiscal_year,
    fiscal_period,
    main_account,
    adjustment_type,
    {{ dim_select(trailing=true) }}
    groupUniqArray(journal_id) as journal_ids,
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
    adjustment_type
    {{- dim_group_by(leading=true) }}
having count() > 1
