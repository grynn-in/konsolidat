{{
    config(
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# PRD-5 R4: Unified consolidated trial balance
   Unions: entity balances + IC eliminations + CTA + topside adjustments #}

{# Layer 1: Entity translated balances #}
with entity_balances as (
    select
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        main_account,
        account_name,
        {{ dim_select() }},
        reporting_currency,
        group_amount as amount,
        'entity' as adjustment_type,
        '' as journal_id
    from {{ ref('gold_consolidated_trial_balance') }}
),

{# Layer 2: IC eliminations #}
ic_elims as (
    select
        consolidation_group,
        '' as data_area_id,
        fiscal_year,
        fiscal_period,
        debit_account as main_account,
        'IC Elimination' as account_name,
        {{ dim_empty_strings() }},
        '' as reporting_currency,
        debit_elimination as amount,
        'ic_elimination' as adjustment_type,
        rule_id as journal_id
    from {{ ref('gold_ic_eliminations') }}

    union all

    select
        consolidation_group,
        '' as data_area_id,
        fiscal_year,
        fiscal_period,
        credit_account as main_account,
        'IC Elimination' as account_name,
        {{ dim_empty_strings() }},
        '' as reporting_currency,
        credit_elimination as amount,
        'ic_elimination' as adjustment_type,
        rule_id as journal_id
    from {{ ref('gold_ic_eliminations') }}
),

{# Layer 3: CTA entries #}
cta_entries as (
    select
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        main_account,
        'CTA' as account_name,
        {{ dim_empty_strings() }},
        reporting_currency,
        cta_amount as amount,
        'cta' as adjustment_type,
        '' as journal_id
    from {{ ref('gold_fx_revaluation') }}
),

{# Layer 4: Top-side adjustments #}
topside as (
    select
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        main_account,
        description as account_name,
        {{ dim_empty_strings() }},
        '' as reporting_currency,
        {{ cast_to_float64('net_amount') }} as amount,
        adjustment_type,
        journal_id
    from {{ ref('gold_consolidation_adjustments') }}
),

{# Union all layers #}
all_layers as (
    select * from entity_balances
    union all
    select * from ic_elims
    union all
    select * from cta_entries
    union all
    select * from topside
)

select * from all_layers
