{{
    config(
        materialized='incremental',
        incremental_strategy='delete+insert',
        unique_key='recid',
        engine=cluster_engine('ReplacingMergeTree(_airbyte_extracted_at)'),
        order_by='(data_area_id, accounting_date, recid)',
        partition_by='toYear(accounting_date)',
        cluster=cluster_name()
    )
}}

select
    {{ cast_to_int64('RecId') }} as recid,
    {{ cast_to_string('dataAreaId') }} as data_area_id,
    {{ cast_to_date('AccountingDate') }} as accounting_date,
    {{ cast_to_string('JournalNumber') }} as journal_number,
    {{ cast_to_string('JournalCategory') }} as journal_category,
    {{ cast_to_string('DocumentNumber') }} as document_number,
    {{ cast_to_date('DocumentDate') }} as document_date,
    {{ cast_to_string('Description') }} as description,
    {{ cast_to_string('PostingLayer') }} as posting_layer,
    {{ cast_to_string('FiscalCalendarPeriod') }} as fiscal_calendar_period,
    {{ cast_to_int64('FiscalCalendarYear') }} as fiscal_calendar_year_recid,
    {{ cast_to_datetime('_airbyte_extracted_at') }} as _airbyte_extracted_at,
    {{ cast_to_string('_airbyte_raw_id') }} as _airbyte_raw_id
from {{ ref('stg_d365_fo__gl_journal_entries') }}

{# CDC delta: reprocess rows extracted at/after the last loaded batch. `>=`
   re-reads the boundary second (toDateTime is second-precision); delete+insert
   on unique_key=recid removes the re-read rows before insert, so no duplicates
   and downstream reads need no FINAL. #}
{% if is_incremental() %}
where {{ cast_to_datetime('_airbyte_extracted_at') }} >= (select max(_airbyte_extracted_at) from {{ this }})
{% endif %}
