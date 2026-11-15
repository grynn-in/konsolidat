{# konsol#348 S3 B13 (QB7 a, BUD-7-a; decided 14 Nov 2026 under Deepak Pai's standing rule): a variance is
   favourable by the account's normal balance, read from the chart (silver_main_accounts.normal_balance, konsol's
   Main Account), on amounts signed debit - credit (QB6 a).

   A credit-normal account (revenue) is favourable when the actual is more credit than the budget: its signed
   actual is below its signed budget (-1,200 against -1,000). A debit-normal account (expense) is favourable
   when the actual is less debit than the budget: again below it (900 against 1,000; 1,200 against 1,000 is
   not). Under debit-positive signs both read "actual below budget"; they are spelled out so the rule reads in
   accounting terms. No favourable direction, so never favourable: a row with no budget, a balance-sheet
   account, and an account whose normal balance is not declared or not in the chart.

   The retired assert_favorable_revenue restated the model's own rule ("Revenue and actual > budget") against
   the model's own columns, so it passed while the model marked less revenue as favourable (the sign was the
   wrong way round). This test derives the expectation from the chart and the amounts, not from the model's
   account_type_name or flag, and its fixtures hold hand-computed rows: revenue 1,200 actual against 1,000
   budget is favourable; expense 1,200 against 1,000 is not. One row per variance row whose flag differs;
   error severity.
   Fixtures: dbt_project/test_fixtures/variance_favorable_signed.sql (build, pass),
   assert_variance_favorable_follows_normal_balance.sql (pass), .must_flag.sql (flag). #}
{{ config(severity='error') }}

with judged as (
    select
        v.data_area_id as data_area_id,
        v.fiscal_year as fiscal_year,
        v.fiscal_period as fiscal_period,
        v.main_account as main_account,
        v.budget_scenario_id as budget_scenario_id,
        v.is_pnl as is_pnl,
        v.actual_amount as actual_amount,
        v.budget_amount as budget_amount,
        toUInt8(v.variance_favorable) as model_favorable,
        am.normal_balance as chart_normal_balance,
        multiIf(
            v.budget_amount is null, toUInt8(0),
            v.is_pnl = 0, toUInt8(0),
            am.normal_balance = 'Credit', toUInt8(v.actual_amount < v.budget_amount),
            am.normal_balance = 'Debit', toUInt8(v.actual_amount < v.budget_amount),
            toUInt8(0)
        ) as expected_favorable
    from {{ ref('gold_variance_analysis') }} as v
    {# join_use_nulls=0: an account not in the chart reads normal_balance '', which is "not declared" #}
    left join {{ ref('silver_main_accounts') }} as am
        on am.main_account_id = v.main_account
)

select
    data_area_id,
    fiscal_year,
    fiscal_period,
    main_account,
    budget_scenario_id,
    chart_normal_balance,
    is_pnl,
    actual_amount,
    budget_amount,
    model_favorable,
    expected_favorable
from judged
where model_favorable != expected_favorable
