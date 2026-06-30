{#
    konsolidat#118 — the legacy `is_credit` flag is retired.

    Since konsolidat#112 silver derives debit/credit purely from the SIGN of the
    (already-signed) accounting_currency_amount; `is_credit` no longer drives the
    split and must not be carried through the GL staging/bronze output. This guard
    fails the build if `is_credit` reappears as a column on the canonical staging
    model or the bronze GL fact, so the dead flag cannot silently creep back.

    Always-on (not opt-in): it asserts a permanent schema contract, returns 0 rows
    once is_credit is gone, and never touches model SQL — full builds are unchanged.
    RED before C1 (is_credit carried through staging→bronze); GREEN after.
#}

{% set stg = ref('stg_gl_entries') %}
{% set bronze = ref('bronze_general_journal_account_entries') %}

select concat(database, '.', table) as model
from system.columns
where name = 'is_credit'
  and (
    (database = '{{ stg.schema }}' and table = '{{ stg.identifier }}')
    or (database = '{{ bronze.schema }}' and table = '{{ bronze.identifier }}')
  )
