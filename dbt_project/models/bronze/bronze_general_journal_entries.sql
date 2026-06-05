{{
    config(
        engine='MergeTree()',
        order_by='(data_area_id, accounting_date, recid)',
        partition_by='toYYYYMM(accounting_date)'
    )
}}

select
    toInt64(RecId) as recid,
    toString(dataAreaId) as data_area_id,
    toDate(AccountingDate) as accounting_date,
    toString(JournalNumber) as journal_number,
    toString(JournalCategory) as journal_category,
    toString(DocumentNumber) as document_number,
    toDate(DocumentDate) as document_date,
    toString(Description) as description,
    toString(PostingLayer) as posting_layer,
    toString(FiscalCalendarPeriod) as fiscal_calendar_period,
    toInt64(FiscalCalendarYear) as fiscal_calendar_year_recid,
    toDateTime(_airbyte_extracted_at) as _airbyte_extracted_at,
    toString(_airbyte_raw_id) as _airbyte_raw_id
from {{ source('airbyte_raw', 'general_journal_entries') }}
