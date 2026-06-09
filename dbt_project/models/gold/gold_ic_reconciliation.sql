{{
    config(
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# PRD-15: IC reconciliation — matched vs unmatched balances per entity pair #}

with ic_account_balances as (
    select
        ctb.consolidation_group,
        ctb.data_area_id,
        ctb.fiscal_year,
        ctb.fiscal_period,
        ctb.main_account,
        sum(ctb.group_amount) as balance
    from {{ ref('gold_consolidated_trial_balance') }} as ctb
    group by
        ctb.consolidation_group,
        ctb.data_area_id,
        ctb.fiscal_year,
        ctb.fiscal_period,
        ctb.main_account
),

{# Cross-join entity pairs to find IC matches #}
entity_pairs as (
    select
        a.consolidation_group,
        a.data_area_id as entity_a,
        b.data_area_id as entity_b,
        a.fiscal_year,
        a.fiscal_period,
        a.main_account as account_a,
        b.main_account as account_b,
        a.balance as balance_a,
        b.balance as balance_b,
        a.balance + b.balance as net_balance,
        case
            when abs(a.balance + b.balance) < 0.01 then 'matched'
            else 'unmatched'
        end as match_status
    from ic_account_balances as a
    inner join ic_account_balances as b
        on a.consolidation_group = b.consolidation_group
        and a.fiscal_year = b.fiscal_year
        and a.fiscal_period = b.fiscal_period
        and a.data_area_id < b.data_area_id
    inner join {{ ref('ic_elimination_rules') }} as icr
        on a.main_account = {{ cast_to_string('icr.debit_account') }}
        and b.main_account = {{ cast_to_string('icr.credit_account') }}
)

select * from entity_pairs
