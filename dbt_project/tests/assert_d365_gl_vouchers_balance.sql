{#
    konsolidat#155 — every D365 voucher nets to zero at staging.

    Silver derives debit/credit from the SIGN of the amount (konsolidat#112), so
    the amount has to arrive signed. The demo generator shipped magnitudes with
    the sign only in IsCredit; every credit was booked as a debit, every trial
    balance went one-sided, and nothing failed until
    assert_silver_gl_debit_credit_balance, three layers down, by entity-year,
    where it was mistaken for "demo-data tension".

    This fails at the source, per voucher, whatever the feed. It deliberately does
    not re-derive the sign from IsCredit: on real D365 that flag can disagree
    with the sign on storno lines (#112/#118, assert_is_credit_retired). A
    correctly signed voucher nets to zero either way.

    Grouped by voucher alone, entity-less headers included: a voucher must
    balance whatever entity it is attributed to.
#}

select
    general_journal_entry_recid as voucher,
    any(entity_id) as entity_id,
    any(journal_number) as journal_number,
    count() as lines,
    sum(amount) as net
from {{ ref('stg_d365_fo__gl_entries') }}
group by general_journal_entry_recid
having abs(sum(amount)) > 0.01
