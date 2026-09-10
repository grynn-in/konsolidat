{{ config(enabled = 'erpnext' in var('erp_sources', ['d365_fo'])) }}
{#
    Enabled here, not in dbt_project.yml: var() inside a dbt_project.yml
    +enabled config does not see the project's own vars: block and silently
    falls back to the default, while this model body does see it. That
    disagreement disabled these models while the canonical loop still
    ref'd them, which failed the whole dbt parse.
#}
{#
    ERPNext legal entities adapter.
    Maps the `Company` doctype → canonical stg_legal_entities schema.

    entity_id is upper(company name) to match the entity_id emitted by
    stg_erpnext__gl_entries / budget_entries (ERPNext Company has no short
    code, so the display name is the canonical key, uppercased for join
    stability across the erpnext models).
#}

select
    'erpnext' as erp_source,
    upper(coalesce(name, '')) as entity_id,
    coalesce(name, '') as entity_name,
    coalesce(default_currency, '') as accounting_currency,
    coalesce(default_currency, '') as reporting_currency,
    '' as party_number,
    coalesce(country, '') as country_region,
    _airbyte_extracted_at as _loaded_at,
    _airbyte_raw_id as _raw_id
from {{ source('erpnext_raw', 'company') }}
