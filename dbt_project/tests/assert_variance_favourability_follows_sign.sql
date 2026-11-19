{# konsolidat#214; konsol#562 E + ii (Deepak Pai, 18 Nov 2026; amends the gate half of BUD-7-a, 7 Nov 2026):
   favourability comes from the variance SIGN only, on amounts signed debit - credit (QB6 a). The account's
   normal_balance no longer gates it. Four states in one String column, never a summable flag:

   - 'favourable': a P&L account whose signed actual is below its signed budget. Below budget is good for
     revenue (more credit) and for cost (less debit) alike.
   - 'unfavourable': a P&L account whose signed actual is above its signed budget.
   - 'on_budget': a P&L account whose actual equals its budget exactly.
   - 'not_applicable': a balance-sheet account, or an account not in the chart (join_use_nulls=0 reads
     is_pnl 0). Only is_pnl decides this.

   No budget line is a budget of ZERO ("Unbudgeted is unfavourable", Deepak Pai, 22 Sep 2026: budget 0,
   actual 10 is an unfavourable variance of 10). A P&L account with a blank normal balance is judged by its
   sign like any other.

   This test derives the expected state from the chart (is_pnl) and the amounts, never from the model's own
   columns, so a model that gates on normal balance, marks a zero variance 'not_applicable', or mislabels a
   balance-sheet account as P&L, is named. One row per variance row whose state differs; error severity.
   Fixtures: dbt_project/test_fixtures/variance_favourability_signed.sql (build, pass),
   assert_variance_favourability_follows_sign.sql (pass), .must_flag.sql (flag 6). #}
{{ config(severity='error') }}

with judged as (
    select
        v.data_area_id as data_area_id,
        v.fiscal_year as fiscal_year,
        v.fiscal_period as fiscal_period,
        v.main_account as main_account,
        v.budget_scenario_id as budget_scenario_id,
        v.is_pnl as is_pnl,
        am.is_pnl as chart_is_pnl,
        v.actual_amount as actual_amount,
        v.budget_amount as budget_amount,
        v.variance_favourability as model_state,
        am.normal_balance as chart_normal_balance,
        multiIf(
            coalesce(am.is_pnl, 0) = 0, 'not_applicable',
            v.actual_amount < coalesce(v.budget_amount, 0), 'favourable',
            v.actual_amount > coalesce(v.budget_amount, 0), 'unfavourable',
            'on_budget'
        ) as expected_state
    from {{ ref('gold_variance_analysis') }} as v
    {# join_use_nulls=0: an account not in the chart reads is_pnl 0, so 'not_applicable' #}
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
    chart_is_pnl,
    is_pnl,
    actual_amount,
    budget_amount,
    model_state,
    expected_state
from judged
where model_state != expected_state
