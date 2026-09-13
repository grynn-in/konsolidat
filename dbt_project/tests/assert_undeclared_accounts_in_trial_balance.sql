{{ config(severity='warn') }}
{#
    konsol#182: every account a trial balance posts to is declared in the
    group chart (konsol Main Account, Published). silver_main_accounts reads
    only that chart, so an undeclared account has no classification: its rows
    stay in the trial balance but reach NEITHER the P&L NOR the balance sheet,
    and consolidation translates them at the closing rate. This names each
    one, with the entities and periods that post to it. The fix is in konsol:
    declare and publish the account (or correct the code in the upload).

    NOT IN, not a LEFT JOIN: under join_use_nulls=0 an unmatched join fills ''
    rather than NULL, so an `is null` test would never fire. That is how
    assert_gl_accounts_in_chart (the same question, as LEFT JOIN ... IS NULL)
    never fired; this test replaces it.

    severity warn, on purpose: this test depends on the model's upstream, so
    at error severity a failure made `dbt build` SKIP the model's downstream,
    leaving the old figures in place and the run half-green.
#}
select
    main_account,
    arraySort(groupUniqArray(data_area_id)) as entities,
    arraySort(groupUniqArray(concat('FY', toString(fiscal_year), ' P', toString(fiscal_period)))) as periods,
    count() as tb_rows,
    'not in the konsol group chart (Main Account): in neither statement until it is declared and published' as problem
from {{ ref('gold_trial_balance') }}
where main_account not in (select main_account_id from {{ ref('silver_main_accounts') }})
group by main_account
