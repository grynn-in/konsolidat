{{
    config(
        materialized='incremental',
        incremental_strategy='delete+insert',
        unique_key=['consolidation_group', 'data_area_id', 'fiscal_year', 'fiscal_period'],
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# A2 / grynn-in/konsolidat#116: incremental-by-period materialization. Inherits
   the scoped slice from the gold_consolidated_trial_balance chokepoint (Layer 1
   entity balances). delete+insert keyed on the close slice
   (consolidation_group, data_area_id, fiscal_year, fiscal_period) replaces only
   the in-scope keys, preserving other slices instead of OVERWRITING the table.
   No vars => every key present => identical to a full table build (opt-in). #}

{# PRD-5 R4: Unified consolidated trial balance
   Unions: entity balances + IC eliminations + CTA + topside adjustments
   PRD-14: + Layer 5: equity method entries
   PRD-11/12: + Layer 6: acquisition/disposal adjustments #}

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

{# Layer 5: Equity method entries (PRD-14) #}
equity_method as (
    select
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        main_account,
        account_name,
        {{ dim_empty_strings() }},
        reporting_currency,
        amount,
        'equity_method' as adjustment_type,
        journal_id
    from {{ ref('gold_equity_method_associates') }}
),

{# Layer 6: Acquisition & disposal adjustments (PRD-11/12) #}
acquisition_disposal as (
    select
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        main_account,
        account_name,
        {{ dim_empty_strings() }},
        '' as reporting_currency,
        adjustment_amount as amount,
        adjustment_type,
        concat('ACQ_', data_area_id) as journal_id
    from {{ ref('gold_acquisition_adjustments') }}

    union all

    select
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        'DISPOSAL' as main_account,
        'Disposal gain/loss' as account_name,
        {{ dim_empty_strings() }},
        '' as reporting_currency,
        gain_loss_amount as amount,
        adjustment_type,
        concat('DSP_', data_area_id) as journal_id
    from {{ ref('gold_disposal_adjustments') }}
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
    union all
    select * from equity_method
    union all
    select * from acquisition_disposal
)

select * from all_layers
