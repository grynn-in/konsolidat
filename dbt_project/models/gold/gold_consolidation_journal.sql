{{
    config(
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# PRD-22: Unified consolidation journal — audit trail of all consolidation entries
   One row per journal entry across all layers #}

select
    consolidation_group,
    data_area_id,
    fiscal_year,
    fiscal_period,
    main_account,
    account_name,
    adjustment_type,
    journal_id,
    reporting_currency,
    case when amount >= 0 then amount else 0 end as debit_amount,
    case when amount < 0 then -amount else 0 end as credit_amount,
    amount as net_amount,
    adjustment_type as entry_source
from {{ ref('gold_fully_consolidated_tb') }}
where adjustment_type != 'entity'
