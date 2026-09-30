{{
    config(
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# PRD-22: Unified consolidation journal — audit trail of all consolidation entries
   One row per journal entry across all layers.

   konsol#305 V05 (batch review 27 Sep finding 2): the topside, reclassification and
   auto_reversal rows come straight from gold_consolidation_adjustments (one row per journal
   line, the journal's own journal_id and line description), not from layer 4 of
   gold_fully_consolidated_tb, which SUMs those lines to the account grain (V03/P6) and reports
   any(journal_id) for the group — two journals on one account, entity and period (ZZJ-00001 and
   ZZJ-00002 on the V03 fixture) collapsed into one row labelled with only one journal name.
   Every other layer (entity, IC elimination, CTA, equity method, acquisition/disposal) is
   unchanged, still read from gold_fully_consolidated_tb.
   assert_consolidation_journal_names_every_journal proves every journal_id in
   gold_consolidation_adjustments is named here. #}

with adjustment_lines as (
    select
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        main_account,
        description as account_name,
        adjustment_type,
        journal_id,
        '' as reporting_currency,
        {{ cast_to_float64('debit_amount') }} as debit_amount,
        {{ cast_to_float64('credit_amount') }} as credit_amount,
        {{ cast_to_float64('net_amount') }} as net_amount,
        adjustment_type as entry_source
    from {{ ref('gold_consolidation_adjustments') }}
),

other_layers as (
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
    where adjustment_type not in ('entity', 'topside', 'reclassification', 'auto_reversal')
)

select * from adjustment_lines
union all
select * from other_layers
