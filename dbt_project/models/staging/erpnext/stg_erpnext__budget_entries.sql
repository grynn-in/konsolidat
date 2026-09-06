{{ config(enabled = 'erpnext' in var('erp_sources', ['d365_fo'])) }}
{#
    Enabled here, not in dbt_project.yml: var() inside a dbt_project.yml
    +enabled config does not see the project's own vars: block and silently
    falls back to the default, while this model body does see it. That
    disagreement disabled these models while the canonical loop still
    ref'd them, which failed the whole dbt parse.
#}
{#
    ERPNext budget entries adapter.
    Maps the `Budget` doctype (flattened to one row per `Budget Account` child
    line) → canonical stg_budget_entries schema.

    The extractor flattens each Budget header against its Budget Account child
    rows, so the raw `budget` table carries the parent fields (company,
    fiscal_year, cost_center, project) denormalized onto every account line
    (account, budget_amount). ERPNext budgets have no posting date — we derive
    one from the fiscal-year start. record_id is a deterministic Int64 surrogate
    from the parent name + account, matching the numeric canonical contract.
#}

select
    'erpnext' as erp_source,
    -- UInt64 surrogate to match the D365 budget adapter's rowNumberInAllBlocks()
    -- type for UNION; modulo keeps it < 2^63 so the downstream toInt64 cast in
    -- bronze cannot overflow.
    toUInt64(cityHash64(concat(coalesce(name, ''), '|', coalesce(account, ''))) % 9223372036854775807) as record_id,
    upper(coalesce(company, '')) as entity_id,
    concat(substring(coalesce(fiscal_year, '1900'), 1, 4), '-01-01') as posting_date,
    coalesce(account, '') as main_account,
    coalesce(budget_amount, 0) as amount,
    coalesce(budget_amount, 0) as transaction_amount,
    '' as transaction_currency,
    coalesce(name, '') as budget_model,
    'Completed' as budget_status,
    coalesce(cost_center, '') as dim_cost_center,
    '' as dim_department,
    _airbyte_extracted_at as _loaded_at,
    _airbyte_raw_id as _raw_id
from {{ source('erpnext_raw', 'budget') }}
