{#
    konsolidat#93: the missing-key query as standalone SQL, for proving
    konsol's rate adoption from clickhouse-client. There is ONE definition,
    macros/governed_rates.sql governed_rate_gaps(); this only renders it:

        dbt compile --select fx_governed_rate_gaps
        # then run target/compiled/open_epm/analyses/fx_governed_rate_gaps.sql

    Zero rows = every translated foreign-currency key has a usable governed
    rate. deploy.sh runs the same macro through fx_precheck().
#}
-- depends_on: {{ ref('gold_trial_balance') }} {{ ref('silver_entity_currencies') }} {{ ref('gold_entity_ownership') }} {{ source('epm_gold', 'consolidation_groups') }} {{ source('epm_staging', 'group_exchange_rates') }} {{ source('epm_gold', 'currencies') }}
select * from ({{ governed_rate_gaps(scoped=false) }}) order by from_currency, to_currency, fy, fp
