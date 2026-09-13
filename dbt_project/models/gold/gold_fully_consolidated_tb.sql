{{
    config(
        materialized='table',
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# #154: a TABLE, rebuilt and swapped in on every run. It carries no
   scope_filter/period_filter of its own: its SELECT always reads every upstream
   row (konsolidat#124), so a scoped close re-derived it in full anyway. As
   delete+insert it only replaced the keys the SELECT produced, and a key that
   left it (an entity that stopped consolidating) kept its rows forever. #}

{# PRD-5 R4: Unified consolidated trial balance
   Unions: entity balances + IC eliminations + CTA + topside adjustments
   PRD-14: + Layer 5: equity method entries
   PRD-11/12: + Layer 6: acquisition/disposal adjustments #}

{# Layer 1: Entity translated balances.
   konsol#159: gold_consolidated_trial_balance has one row per intercompany
   partner. This layer is per account, so it sums over the partners. Passed
   through row by row, gold_consolidated_ytd ran a separate running total
   per partner row (#175 review: 250 instead of 150). #}
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
        sum(group_amount) as amount,
        'entity' as adjustment_type,
        '' as journal_id
    from {{ ref('gold_consolidated_trial_balance') }}
    group by
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        main_account,
        account_name,
        {{ dim_group_by() }},
        reporting_currency
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

{# Layer 6: Acquisition & disposal adjustments (PRD-11/12).
   #175 re-review F3: the pnl_proration rows are one per consolidated row,
   and gold_consolidated_trial_balance has a row per intercompany partner,
   so they are summed to the account grain here, like layer 1. Otherwise
   gold_consolidated_ytd ran a separate running total per row. #}
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
        sum(adjustment_amount) as amount,
        adjustment_type,
        concat('ACQ_', data_area_id) as journal_id
    from {{ ref('gold_acquisition_adjustments') }}
    group by consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account,
             account_name, adjustment_type

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
