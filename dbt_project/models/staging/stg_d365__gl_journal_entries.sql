{#
    GL Journal Entries staging model.
    Maps GeneralJournalEntryBiEntities fields to general_journal_entries schema.
    SourceKey → RecId, SubledgerVoucherDataAreaId → dataAreaId.
#}

select
    SourceKey as RecId,
    upper(coalesce(SubledgerVoucherDataAreaId, '')) as dataAreaId,
    toString(substring(coalesce(toString(AccountingDate), '1900-01-01'), 1, 10)) as AccountingDate,
    coalesce(JournalNumber, '') as JournalNumber,
    coalesce(JournalCategory, '') as JournalCategory,
    coalesce(DocumentNumber, '') as DocumentNumber,
    toString(substring(coalesce(toString(DocumentDate), '1900-01-01'), 1, 10)) as DocumentDate,
    coalesce(SubledgerVoucher, '') as Description,
    coalesce(PostingLayer, '') as PostingLayer,
    toString(coalesce(FiscalCalendarPeriod, 0)) as FiscalCalendarPeriod,
    coalesce(FiscalCalendarYear, 0) as FiscalCalendarYear,
    _airbyte_extracted_at,
    _airbyte_raw_id
from {{ source('d365_raw', 'GeneralJournalEntryBiEntities') }}
