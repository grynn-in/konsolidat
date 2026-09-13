{{ config(severity='warn') }}

-- depends_on: {{ source('epm_staging', 'main_accounts') }} {{ ref('silver_main_accounts') }}

{#
    konsol#182: every Published declaration in the governed chart
    (epm_staging.main_accounts) is one silver can use. This names each one
    that isn't, and why (governed_chart_problems): duplicate rows that
    disagree, a statement_section or fx_method outside the vocabulary, a P&L
    account at the historical rate or a balance-sheet account at the average
    rate. The fix is in konsol: correct or unpublish the Main Account.

    severity warn, on purpose: this test depends on the model's upstream, so
    at error severity a failure made `dbt build` SKIP the model and its
    downstream, leaving the old figures in place and the run half-green. The
    model decides: its pre_hook (governed_chart_guard, the same query) stops
    the build before silver_main_accounts is replaced.
#}
select main_account, problem
from ({{ governed_chart_problems() }})
