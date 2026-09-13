{{ config(severity='warn') }}
{#
    Every chart account (silver_main_accounts already drops Total accounts) is
    exactly one of is_pnl / is_balance_sheet. An account that is neither drops
    out of the P&L, the balance sheet and cash-flow net income, and is
    translated at the closing rate; one that is both is counted twice. This
    names each such account and its raw account_type, so the fix is to add
    that type to the classification lists in silver_main_accounts (it is how
    ERPNext's 'Income' root_type went unclassified).

    severity warn, on purpose: this test depends on the model's upstream, so
    at error severity a failure made `dbt build` SKIP the model's downstream,
    leaving the old figures in place and the run half-green.
#}
select
    main_account_id,
    account_name,
    account_type,
    account_type_name,
    if(
        is_pnl and is_balance_sheet,
        'classified as both P&L and balance sheet',
        'classified as neither P&L nor balance sheet (unrecognised account_type)'
    ) as problem
from {{ ref('silver_main_accounts') }}
where toUInt8(is_pnl) + toUInt8(is_balance_sheet) != 1
