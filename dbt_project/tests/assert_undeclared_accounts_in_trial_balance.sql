{{ config(severity='warn') }}
{#
    konsol#182, informational: the trial-balance accounts the group chart
    does not declare. silver_main_accounts classifies such an account from the
    ERP's chart (chart_origin = 'erp'), exactly as before the governed chart
    existed. This lists each one, with the entities that post to it, so group
    finance can declare it in konsol's Main Account and make the
    classification a decision rather than an inference. Nothing is wrong with
    the figures.

    severity warn, on purpose: this test depends on the model's upstream, so
    at error severity a failure made `dbt build` SKIP the model's downstream,
    leaving the old figures in place and the run half-green.
#}
select
    main_account,
    any(account_name) as account_name,
    any(account_type_name) as account_type_name,
    arraySort(groupUniqArray(data_area_id)) as entities
from {{ ref('gold_trial_balance') }}
where main_account in (
    select main_account_id from {{ ref('silver_main_accounts') }} where chart_origin = 'erp'
)
group by main_account
