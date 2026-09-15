{{
    config(
        materialized='incremental',
        incremental_strategy='delete+insert',
        unique_key='recid',
        engine=cluster_engine('ReplacingMergeTree(_airbyte_extracted_at)'),
        order_by='(data_area_id, accounting_date, recid)',
        partition_by='toYear(accounting_date)',
        cluster=cluster_name(),
        on_schema_change='append_new_columns'
    )
}}

{# konsol#159: on_schema_change adds partner_data_area_id to a table built
   before it existed; an incremental run would otherwise drop the new column
   silently (dbt inserts only the columns the target already has). #}

{#
    Consumes canonical stg_gl_entries for ERP-agnostic columns, for every ERP
    in `erp_sources` (it is already an empty typed relation when none is
    listed, macros/erp_sources.sql), so it is read unconditionally.

    Joins the D365 F&O adapter for reporting_currency_amount and
    general_journal_entry_recid (D365-specific fields) only when `d365_fo`
    is listed; otherwise both are 0.
#}

{% set d365_joined = 'd365_fo' in var('erp_sources', []) %}

select
    {{ cast_to_int64('gl.record_id') }} as recid,
    {{ cast_to_string('gl.entity_id') }} as data_area_id,
    {{ cast_to_date('gl.posting_date') }} as accounting_date,
    {{ cast_to_string('gl.main_account') }} as main_account,
    {{ cast_to_decimal128('gl.amount', 2) }} as accounting_currency_amount,
    {{ cast_to_decimal128('coalesce(d365.reporting_currency_amount, 0)' if d365_joined else '0', 2) }} as reporting_currency_amount,
    {{ cast_to_decimal128('gl.transaction_currency_amount', 2) }} as transaction_currency_amount,
    {{ cast_to_string('gl.transaction_currency') }} as transaction_currency_code,
    {{ cast_to_string('gl.posting_type') }} as posting_type,
    {{ cast_to_int64('coalesce(d365.general_journal_entry_recid, 0)' if d365_joined else '0') }} as general_journal_entry_recid,
    {{ cast_to_string('gl.ledger_account') }} as ledger_account,
    {{ cast_to_string('gl.description') }} as description,
    {# '' = no partner (the canonical column is NULL for every ERP today) #}
    {{ cast_to_string("coalesce(gl.partner_data_area_id, '')") }} as partner_data_area_id,
    {{ dim_select_from_source(prefix='gl.') }},
    {{ cast_to_datetime('gl._loaded_at') }} as _airbyte_extracted_at,
    {{ cast_to_string('gl._raw_id') }} as _airbyte_raw_id
from {{ ref('stg_gl_entries') }} gl
{% if 'd365_fo' in var('erp_sources', []) %}
left join {{ ref('stg_d365_fo__gl_entries') }} d365
    on gl.record_id = d365.record_id
    and gl.erp_source = 'd365_fo'
{% endif %}

{# CDC delta: reprocess rows extracted at/after the last loaded batch. `>=`
   re-reads the boundary second (toDateTime is second-precision) so same-second
   rows are never skipped; delete+insert on unique_key=recid removes the
   re-read rows before insert, so there are no duplicates and downstream reads
   need no FINAL. #}
{% if is_incremental() %}
where {{ cast_to_datetime('gl._loaded_at') }} >= (select max(_airbyte_extracted_at) from {{ this }})
{% endif %}
