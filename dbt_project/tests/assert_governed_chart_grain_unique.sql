{{ config(severity='warn') }}

-- depends_on: {{ source('epm_staging', 'main_accounts') }} {{ ref('silver_main_accounts') }}

{#
    konsol#182: the governed chart (epm_staging.main_accounts) has one
    Published row per account code. konsol writes it with TRUNCATE+INSERT,
    and two syncs that race can double a row. Silver keeps one of identical
    duplicates (limit 1 by), and its guard refuses duplicates that disagree on
    what the account is; this names every duplicated code, identical or not,
    with the number of distinct versions, so the table can be repaired with
    konsol's reconcile_all() before the duplicates disagree.

    severity warn, on purpose: this test depends on the model's upstream, so
    at error severity a failure made `dbt build` SKIP the model's downstream,
    leaving the old figures in place and the run half-green.
#}
{%- set rel = governed_chart_relation() %}
{% if rel is none %}
select '' as main_account, toUInt64(0) as published_rows, toUInt64(0) as distinct_versions
where 0
{% else %}
select
    main_account,
    count() as published_rows,
    uniqExact(tuple(*)) as distinct_versions
from {{ rel }}
where status = 'Published'
group by main_account
having count() > 1
{% endif %}
