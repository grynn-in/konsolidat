{{
    config(
        engine='MergeTree()',
        order_by='(main_account_id)',
        pre_hook=["{{ governed_chart_guard() }}"]
    )
}}

{# konsol#182 — what each account is. The one answer, and one source: the group
   chart governed in konsol (Main Account, Published), written through to
   epm_staging.main_accounts. Declarations, not inferences. No ERP chart is
   read: every source follows the shape konsol defines, and the canonical way
   in is the trial balance upload.

   An account that is not declared in konsol is not here. Its trial-balance
   rows reach neither statement; assert_undeclared_accounts_in_trial_balance
   names each one. Group (heading) nodes are not posted to and are left out.

   The first eleven columns are the long-standing contract that every
   downstream model reads (names and types unchanged); their values now come
   from the declaration. The rest are new and stay at the end.
   governed_chart_guard (pre_hook) refuses the build, before this table is
   replaced, when a declaration is unusable. #}

-- depends_on: {{ source('epm_staging', 'main_accounts') }}
{%- set governed_rel = governed_chart_relation() %}

with governed as (
{%- if governed_rel %}
    select distinct
        main_account as main_account_id,
        account_name,
        account_type,
        account_type as account_type_name,
        toUInt8(statement_section = 'Profit and Loss') as is_pnl,
        toUInt8(statement_section = 'Balance Sheet') as is_balance_sheet,
        toUInt8(fx_method = 'historical') as is_equity,
        main_account_category,
        normal_balance as debit_credit_default,
        chart_of_accounts,
        toInt8(is_suspended) as is_suspended,
        statement_section, sub_section, normal_balance, time_balance, fx_method,
        toUInt8(is_posting) as is_posting,
        parent_account,
        toUInt8(allow_ic) as allow_ic,
        cf_category, cf_line_item,
        toUInt8(is_cash) as is_cash
    from {{ source('epm_staging', 'main_accounts') }}
    where status = 'Published' and is_group = 0
    {# Two concurrent TRUNCATE+INSERT syncs can double a row. The guard refuses
       Published duplicates that differ in ANY column, so only identical copies
       reach here, and DISTINCT collapses them deterministically (limit 1 by
       would keep an arbitrary one). Were the guard ever bypassed, DISTINCT
       keeps both versions and unique_silver_main_accounts_main_account_id
       names the code, rather than one silently winning. #}
{%- else %}
    {# the table does not exist yet (konsol has not created it): no chart, and
       the same columns and types (the assert_ic_difference_account_in_chart
       pattern) #}
    select '' as main_account_id, '' as account_name, '' as account_type, '' as account_type_name,
           toUInt8(0) as is_pnl, toUInt8(0) as is_balance_sheet, toUInt8(0) as is_equity,
           '' as main_account_category, '' as debit_credit_default, '' as chart_of_accounts,
           toInt8(0) as is_suspended, '' as statement_section, '' as sub_section,
           '' as normal_balance, '' as time_balance, '' as fx_method, toUInt8(0) as is_posting,
           '' as parent_account, toUInt8(0) as allow_ic, '' as cf_category, '' as cf_line_item,
           toUInt8(0) as is_cash
    where 0
{%- endif %}
)

select * from governed
