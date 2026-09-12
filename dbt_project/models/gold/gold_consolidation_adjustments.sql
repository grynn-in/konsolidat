{{
    config(
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# PRD-5: Top-side journal adjustments from the Consolidation Adjustment doctype
   PRD-16: Workflow status filter — only Approved/Reversed flow through
           Auto-reversal generation for journals with auto_reverse_period > 0 #}

{# konsolidat#146: the seed half is gone.

   It read `ref('consolidation_adjustments')` — a CSV materialising into
   epm_gold.consolidation_adjustments, the same relation konsol's legacy
   write-through targeted — and it labelled every row `'Approved'`
   unconditionally, while the staging half filters on the real workflow status.
   It applied only when the staging table happened to be empty, the silent
   fallback F3 removed from gold_consolidation_hierarchy.

   The eight demo rows it carried are not recreated: six of them posted to a
   consolidation group `GLOBAL` and an entity `GROUP` that exist nowhere in the
   Consolidation Group tree, and a top-side journal is transactional data, not
   configuration to ship. #}
with staging_adjustments as (
    select
        consolidation_group,
        adjustment_type,
        journal_id,
        data_area_id,
        fiscal_year,
        fiscal_period,
        main_account,
        debit_amount,
        credit_amount,
        debit_amount - credit_amount as net_amount,
        description,
        posted_by,
        status,
        approved_by,
        reversal_journal_id,
        auto_reverse_period
    from {{ source('epm_staging', 'consolidation_adjustments') }}
    where status in ('Approved', 'Reversed')
),

{# PRD-16: Auto-reversal — generate reversing entries for Approved journals
   with auto_reverse_period > 0. Reversal posts in period + auto_reverse_period. #}
auto_reversals as (
    select
        consolidation_group,
        'auto_reversal' as adjustment_type,
        concat(journal_id, '_REV') as journal_id,
        data_area_id,
        case
            when fiscal_period + auto_reverse_period > 12
            then fiscal_year + 1
            else fiscal_year
        end as fiscal_year,
        case
            when fiscal_period + auto_reverse_period > 12
            then toUInt8(fiscal_period + auto_reverse_period - 12)
            else toUInt8(fiscal_period + auto_reverse_period)
        end as fiscal_period,
        main_account,
        staging_adjustments.credit_amount as debit_amount,
        staging_adjustments.debit_amount as credit_amount,
        staging_adjustments.credit_amount - staging_adjustments.debit_amount as net_amount,
        concat('Auto-reversal of ', journal_id) as description,
        'system' as posted_by,
        'Approved' as status,
        '' as approved_by,
        journal_id as reversal_journal_id,
        toUInt8(0) as auto_reverse_period
    from staging_adjustments
    where auto_reverse_period > 0
      and status = 'Approved'
      and reversal_journal_id = ''
),

{# Use staging if populated, otherwise seed #}
all_adjustments as (
    select * from staging_adjustments

    union all

    select * from auto_reversals
)

select * from all_adjustments
