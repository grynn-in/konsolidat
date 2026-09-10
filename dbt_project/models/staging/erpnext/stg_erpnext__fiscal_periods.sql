{{ config(enabled = 'erpnext' in var('erp_sources', ['d365_fo'])) }}
{#
    Enabled here, not in dbt_project.yml: var() inside a dbt_project.yml
    +enabled config does not see the project's own vars: block and silently
    falls back to the default, while this model body does see it. That
    disagreement disabled these models while the canonical loop still
    ref'd them, which failed the whole dbt parse.
#}
{#
    ERPNext fiscal periods adapter.
    Maps the `Fiscal Year` doctype → canonical stg_fiscal_periods schema.

    ERPNext fiscal years are named ranges ("2024-2025") with explicit start/end
    dates. The name doubles as both calendar_id and the canonical fiscal_year
    label (canonical fiscal_periods.fiscal_year is a string, unlike the numeric
    fiscal_year on gl_entries).
#}

select
    'erpnext' as erp_source,
    coalesce(name, '') as calendar_id,
    coalesce(name, '') as calendar_name,
    coalesce(name, '') as fiscal_year,
    toString(substring(coalesce(toString(year_start_date), '1900-01-01'), 1, 10)) as start_date,
    toString(substring(coalesce(toString(year_end_date), '2099-12-31'), 1, 10)) as end_date,
    _airbyte_extracted_at as _loaded_at,
    _airbyte_raw_id as _raw_id
from {{ source('erpnext_raw', 'fiscal_year') }}
