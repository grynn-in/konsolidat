{#
    GL Journal Entries staging model.
    Maps GeneralJournalEntryBiEntities fields to general_journal_entries schema.
    SourceKey → RecId, SubledgerVoucherDataAreaId → dataAreaId.
#}

select
    SourceKey as RecId,
    upper(coalesce(SubledgerVoucherDataAreaId, '')) as dataAreaId,
    AccountingDate,
    coalesce(JournalNumber, '') as JournalNumber,
    coalesce(JournalCategory, '') as JournalCategory,
    coalesce(DocumentNumber, '') as DocumentNumber,
    DocumentDate,
    coalesce(SubledgerVoucher, '') as Description,
    coalesce(PostingLayer, '') as PostingLayer,
    toString(coalesce(FiscalCalendarPeriod, 0)) as FiscalCalendarPeriod,
    coalesce(FiscalCalendarYear, 0) as FiscalCalendarYear,
    _airbyte_extracted_at,
    _airbyte_raw_id
from {{ source('d365_raw', 'general_journal_entry_bi_entities') }}
