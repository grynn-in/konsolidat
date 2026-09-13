{# ============================================================
   Intercompany helpers (konsolidat#148, konsol#159)

   An account is intercompany because it is flagged in the group chart
   (decision 3, 13 Sep 2026): konsol's Intercompany Account doctype, written
   through to epm_staging.intercompany_accounts. Each Published row names an
   account and the counterpart the PARTNER books the other side on ('' = the
   same account). A pair is symmetric, so the counterpart is intercompany too.
   ============================================================ #}

{# One row per intercompany account: (account, counterpart). konsol refuses
   an account in two pairs; any() keeps this one-row-per-account even if a
   conflict slips through, and assert_ic_account_in_one_pair names it. #}
{% macro ic_account_map() %}
    select account, any(cp) as counterpart
    from (
        select
            main_account as account,
            if(counterpart_account = '', main_account, counterpart_account) as cp
        from {{ source('epm_staging', 'intercompany_accounts') }}
        where status = 'Published'
        union all
        select
            counterpart_account as account,
            main_account as cp
        from {{ source('epm_staging', 'intercompany_accounts') }}
        where status = 'Published'
          and counterpart_account != ''
          and counterpart_account != main_account
    )
    group by account
{% endmacro %}
