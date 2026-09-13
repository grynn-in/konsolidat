{{
    config(
        engine='MergeTree()',
        order_by='(main_account_id)',
        pre_hook=["{{ governed_chart_guard() }}"]
    )
}}

{# konsol#182 — what each account is. The one answer. Two sources, the
   silver_entity_currencies pattern (konsol#110):
   * epm_staging.main_accounts — the group chart governed in konsol (Main
     Account, Published). Declarations, not inferences.
   * bronze_main_accounts — the ERP's chart, the fallback for an account the
     group has not declared, classified exactly as before.
   A declared account takes ALL its attributes from konsol. Precedence by NOT IN,
   never a LEFT JOIN: join_use_nulls=0 fills '' and coalesce never falls through.
   Group (heading) nodes are not posted to and are left out, as ERP Total
   accounts always were. The first eleven columns are the silver contract; the
   rest are new and stay at the end. Both branches give every column the same
   type (UNION ALL would otherwise widen it: Int8 with UInt8 is Int16).
   governed_chart_guard (pre_hook) refuses the build, before this table is
   replaced, when a declaration is unusable. #}

-- depends_on: {{ source('epm_staging', 'main_accounts') }}
{%- set governed_rel = governed_chart_relation() %}

with erp_deduped as (
    select
        *,
        row_number() over (partition by main_account_id order by chart_of_accounts) as rn
    from {{ ref('bronze_main_accounts') }}
    where account_type != '7' and account_type != 'Total'  -- Exclude total accounts
),

{# Its own CTE: deriving fx_method from is_equity in the SELECT that defines
   is_equity risks CYCLIC_ALIASES. #}
erp_classified as (
    select
        main_account_id,
        account_name,
        account_type,
        {{ map_account_type('account_type') }} as account_type_name,
        -- Classification flags for filtering. 'Income' is ERPNext's root_type for
        -- revenue accounts (stg_erpnext__accounts passes root_type through); every
        -- account must be exactly one of is_pnl / is_balance_sheet
        -- (tests/assert_every_account_is_pnl_or_balance_sheet.sql).
        account_type in ('0', '1', '2', 'ProfitAndLoss', 'Revenue', 'Income', 'Expense') as is_pnl,
        account_type in ('3', '4', '5', '6', 'BalanceSheet', 'Asset', 'Liability', 'Equity') as is_balance_sheet,
        -- PRD-10: Equity flag for historical rate translation (IAS 21)
        account_type in ('6', 'Equity') as is_equity,
        main_account_category,
        debit_credit_default,
        chart_of_accounts,
        is_suspended
    from erp_deduped
    where rn = 1
),

erp as (
    select
        main_account_id, account_name, account_type, account_type_name,
        is_pnl, is_balance_sheet, is_equity,
        main_account_category, debit_credit_default, chart_of_accounts, is_suspended,
        multiIf(is_pnl = 1, 'Profit and Loss', is_balance_sheet = 1, 'Balance Sheet', '') as statement_section,
        '' as sub_section,
        '' as normal_balance,
        multiIf(is_pnl = 1, 'flow', is_balance_sheet = 1, 'balance', '') as time_balance,
        {{ erp_fx_method('is_equity', 'is_balance_sheet', 'is_pnl') }} as fx_method,
        toUInt8(1) as is_posting,
        '' as parent_account,
        toUInt8(0) as allow_ic,
        '' as cf_category,
        '' as cf_line_item,
        toUInt8(0) as is_cash,
        'erp' as chart_origin
    from erp_classified
),

governed as (
{%- if governed_rel %}
    select
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
        toUInt8(is_cash) as is_cash,
        'konsol' as chart_origin
    from {{ source('epm_staging', 'main_accounts') }}
    where status = 'Published' and is_group = 0
    {# two concurrent TRUNCATE+INSERT syncs can double a row; the guard stops a
       DISAGREEING duplicate, identical ones collapse here #}
    order by main_account
    limit 1 by main_account
{%- else %}
    {# the table does not exist yet: no declarations (the
       assert_ic_difference_account_in_chart.sql pattern) #}
    select '' as main_account_id, '' as account_name, '' as account_type, '' as account_type_name,
           toUInt8(0) as is_pnl, toUInt8(0) as is_balance_sheet, toUInt8(0) as is_equity,
           '' as main_account_category, '' as debit_credit_default, '' as chart_of_accounts,
           toInt8(0) as is_suspended, '' as statement_section, '' as sub_section,
           '' as normal_balance, '' as time_balance, '' as fx_method, toUInt8(0) as is_posting,
           '' as parent_account, toUInt8(0) as allow_ic, '' as cf_category, '' as cf_line_item,
           toUInt8(0) as is_cash, 'konsol' as chart_origin
    where 0
{%- endif %}
)

select * from governed
union all
select * from erp
where main_account_id not in (select main_account_id from governed)
