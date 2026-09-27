{{
    config(
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# PRD-5: Top-side journal adjustments from the Consolidation Adjustment doctype
   PRD-16: Workflow status filter — only Approved/Reversed flow through
   konsol#305-D2-11: an Approved journal names its reversal period
           (reverse_fiscal_year / reverse_fiscal_period; 0/0 = none). Each of
           its lines gets one auto_reversal row in exactly that period, debit
           and credit swapped, journal_id kept (P26). The old `+N periods`
           arithmetic is gone. Every input column is qualified: an unqualified
           name bound to the output alias (analyzer on,
           prefer_column_name_to_alias=0), so the old filter read toUInt8(0)
           and generated no reversal at all (#304 fault 1). #}

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
        sa.consolidation_group as consolidation_group,
        sa.adjustment_type as adjustment_type,
        sa.journal_id as journal_id,
        sa.data_area_id as data_area_id,
        sa.fiscal_year as fiscal_year,
        sa.fiscal_period as fiscal_period,
        sa.main_account as main_account,
        sa.debit_amount as debit_amount,
        sa.credit_amount as credit_amount,
        sa.debit_amount - sa.credit_amount as net_amount,
        sa.description as description,
        sa.posted_by as posted_by,
        sa.status as status,
        sa.approved_by as approved_by,
        sa.reversal_journal_id as reversal_journal_id,
        sa.reverse_fiscal_year as reverse_fiscal_year,
        sa.reverse_fiscal_period as reverse_fiscal_period
    from {{ source('epm_staging', 'consolidation_adjustments') }} as sa
    where sa.status in ('Approved', 'Reversed')
),

auto_reversals as (
    select
        s.consolidation_group as consolidation_group,
        'auto_reversal' as adjustment_type,
        s.journal_id as journal_id,
        s.data_area_id as data_area_id,
        s.reverse_fiscal_year as fiscal_year,
        s.reverse_fiscal_period as fiscal_period,
        s.main_account as main_account,
        s.credit_amount as debit_amount,
        s.debit_amount as credit_amount,
        s.credit_amount - s.debit_amount as net_amount,
        concat('Auto-reversal of ', s.journal_id) as description,
        'system' as posted_by,
        'Approved' as status,
        '' as approved_by,
        s.journal_id as reversal_journal_id,
        toUInt16(0) as reverse_fiscal_year,
        toUInt8(0) as reverse_fiscal_period
    from staging_adjustments as s
    where s.reverse_fiscal_year > 0
      and s.status = 'Approved'
      and s.reversal_journal_id = ''
),

all_adjustments as (
    select * from staging_adjustments
    union all
    select * from auto_reversals
)

select * from all_adjustments
