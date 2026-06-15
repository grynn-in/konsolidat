{{
    config(
        materialized='incremental',
        incremental_strategy='delete+insert',
        unique_key='recid',
        engine='ReplacingMergeTree(_airbyte_extracted_at)',
        order_by='(data_area_id, accounting_date, recid)',
        partition_by='toYear(accounting_date)'
    )
}}

{#
    Consumes canonical stg_gl_entries for ERP-agnostic columns.
    Joins D365 F&O adapter directly for reporting_currency_amount
    and general_journal_entry_recid (D365-specific fields).
#}

select
    {{ cast_to_int64('gl.record_id') }} as recid,
    {{ cast_to_string('gl.entity_id') }} as data_area_id,
    {{ cast_to_date('gl.posting_date') }} as accounting_date,
    {{ cast_to_string('gl.main_account') }} as main_account,
    {{ cast_to_decimal128('gl.amount', 2) }} as accounting_currency_amount,
    {{ cast_to_decimal128('coalesce(d365.reporting_currency_amount, 0)', 2) }} as reporting_currency_amount,
    {{ cast_to_decimal128('gl.transaction_currency_amount', 2) }} as transaction_currency_amount,
    {{ cast_to_string('gl.transaction_currency') }} as transaction_currency_code,
    {{ cast_to_string('gl.posting_type') }} as posting_type,
    {{ cast_to_int64('coalesce(d365.general_journal_entry_recid, 0)') }} as general_journal_entry_recid,
    {{ cast_to_string('gl.ledger_account') }} as ledger_account,
    {{ cast_to_string('gl.description') }} as description,
    {{ dim_select_from_source(prefix='gl.') }},
    {{ cast_to_int8('gl.is_credit') }} as is_credit,
    {{ cast_to_datetime('gl._loaded_at') }} as _airbyte_extracted_at,
    {{ cast_to_string('gl._raw_id') }} as _airbyte_raw_id
from {{ ref('stg_gl_entries') }} gl
left join {{ ref('stg_d365_fo__gl_entries') }} d365
    on gl.record_id = d365.record_id
    and gl.erp_source = 'd365_fo'

{# CDC delta: reprocess rows extracted at/after the last loaded batch. `>=`
   re-reads the boundary second (toDateTime is second-precision) so same-second
   rows are never skipped; delete+insert on unique_key=recid removes the
   re-read rows before insert, so there are no duplicates and downstream reads
   need no FINAL. #}
{% if is_incremental() %}
where {{ cast_to_datetime('gl._loaded_at') }} >= (select max(_airbyte_extracted_at) from {{ this }})
{% endif %}
