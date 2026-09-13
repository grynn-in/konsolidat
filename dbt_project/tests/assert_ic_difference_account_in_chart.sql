{{ config(severity='warn') }}

{#
    #175 re-review: a group's intercompany-difference account is in the group
    chart. konsol checks it when the account is set, but the chart
    (silver_main_accounts, from the ERP) can drop the account later, and
    differences would then be booked to an account no report shows. A
    warning, not an error: the eliminations still net to zero.

    The column is konsol#159's; on a volume konsol has not upgraded yet there
    is nothing to check.
#}

{% set has_column = false %}
{% if execute %}
    {% set group_columns = adapter.get_columns_in_relation(source('epm_gold', 'consolidation_groups')) | map(attribute='name') | list %}
    {% set has_column = 'ic_difference_account' in group_columns %}
{% endif %}

{% if has_column %}
select consolidation_group, ic_difference_account
from {{ source('epm_gold', 'consolidation_groups') }}
where data_area_id = ''
  and ic_difference_account != ''
  and ic_difference_account not in (select main_account_id from {{ ref('silver_main_accounts') }})
{% else %}
select '' as consolidation_group, '' as ic_difference_account where 0
{% endif %}
