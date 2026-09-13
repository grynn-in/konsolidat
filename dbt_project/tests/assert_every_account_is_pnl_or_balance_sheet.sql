{{ config(severity='warn') }}
{#
    Every chart account is exactly one of is_pnl / is_balance_sheet. An
    account that is neither drops out of the P&L, the balance sheet and
    cash-flow net income, and is translated at the closing rate; one that is
    both appears in both the P&L and the balance sheet (and takes the closing
    rate). This names each such account and its account_type.

    konsol#182: silver_main_accounts is the konsol group chart, and both flags
    come from the declared statement_section. governed_chart_guard refuses the
    build for a Published leaf whose section is outside the two, so this is the
    second line of defence: a row here means the guard was bypassed. The fix
    is the account's declaration in konsol's Main Account.

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
        'classified as neither P&L nor balance sheet'
    ) as problem
from {{ ref('silver_main_accounts') }}
where toUInt8(is_pnl) + toUInt8(is_balance_sheet) != 1
