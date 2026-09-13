{#
    konsolidat#158: every ERP's GL nets to zero at the canonical boundary.

    The adapter contract (models/staging/README.md) says each adapter delivers
    `amount` SIGNED, debit positive and credit negative. Silver splits it into
    debit/credit by sign (konsolidat#112), and nothing downstream re-derives
    the sign. A source that ships magnitudes therefore books every credit as a
    debit (konsolidat#155). This test checks the contract for every source in
    erp_sources at once, over the canonical union, so a new adapter is covered
    the day it is enabled.

    Grain: erp_source, entity_id, journal_number, the finest posting unit every
    adapter exposes (ERPNext voucher_no, D365 JournalNumber). A D365 journal is
    a set of balanced vouchers, so it balances too. D365 keeps its finer
    per-voucher test, assert_d365_gl_vouchers_balance, which also covers the
    entity-less headers this model drops (#105).
#}

select
    erp_source,
    entity_id,
    journal_number,
    count() as lines,
    sum(amount) as net
from {{ ref('stg_gl_entries') }}
group by erp_source, entity_id, journal_number
having abs(sum(amount)) > 0.01
