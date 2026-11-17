{# konsolidat#214; konsol#348 S6 WB1 (S6-Q4 a, taken under Deepak Pai's standing rule, 17 Nov 2026; BUD-7-a,
   Deepak Pai, 7 Nov 2026): a variance is favourable by the account's normal balance, read from the chart
   (silver_main_accounts.normal_balance, konsol's Main Account), on amounts signed debit - credit (QB6 a), and
   favourability is THREE states in one String column, never a summable flag:

   - 'favourable': the signed actual is below the signed budget. A credit-normal account (revenue) is favourable
     when the actual is more credit than the budget (-1,200 against -1,000); a debit-normal account (expense)
     when the actual is less debit (900 against 1,000). Under debit-positive signs both read "actual below
     budget"; they are spelled out so the rule reads in accounting terms.
   - 'unfavourable': the signed actual is above the signed budget (1,200 costs against 1,000; -800 revenue
     against -1,000).
   - 'not_applicable': no favourable direction. No budget, a balance-sheet account, an account whose normal
     balance is not declared or not in the chart (join_use_nulls=0 reads ''), and a zero variance (the
     statement shows "On budget" for it; the warehouse column does not distinguish it, as the yml declares).

   The retired Bool (variance_favorable) read false for "unfavourable" and for "no direction" alike, and konsol
   registered it as a sum Measure, which added flags together (konsolidat#214). This test derives the expected
   state from the chart and the amounts, never from the model's own column, so a model that guesses a direction
   for an undeclared account, or marks a zero variance either way, is named. One row per variance row whose
   state differs; error severity.
   Fixtures: dbt_project/test_fixtures/variance_favourability_signed.sql (build, pass),
   assert_variance_favourability_follows_normal_balance.sql (pass), .must_flag.sql (flag 3). #}
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
        v.variance_favourability as model_state,
        am.normal_balance as chart_normal_balance,
        multiIf(
            v.budget_amount is null, 'not_applicable',
            v.is_pnl = 0, 'not_applicable',
            am.normal_balance not in ('Credit', 'Debit'), 'not_applicable',
            v.actual_amount < v.budget_amount, 'favourable',
            v.actual_amount > v.budget_amount, 'unfavourable',
            'not_applicable'
        ) as expected_state
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
    model_state,
    expected_state
from judged
where model_state != expected_state
