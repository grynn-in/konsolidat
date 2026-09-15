{{
    config(
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# PRD-12: Disposal & deconsolidation — EMPTIED by konsolidat#198 (row J6).

   This model used to post two one-sided P&L amounts per disposal, keyed on
   the Ownership Period's is_disposal / disposal_date and on the month of
   that date: 'disposal_gain_loss' (price − net assets × share − goodwill)
   and 'cta_recycling' (−Σ CTA). gold_fully_consolidated_tb carried them on
   a pseudo-account 'DISPOSAL', so the group balance sheet never balanced in
   a disposal period and the disposed entity's balances were never taken
   out (#180).

   Everything it provided now comes from gold_business_disposal_journal, the
   balanced journal posted from the submitted Business Disposal
   (epm_staging.business_disposals): derecognition of the entity's
   balance-sheet accounts, goodwill net of amortisation, FVA, CTA recycling,
   NCI, proceeds and the gain or loss as the balancing line, in the period
   epm_staging.fiscal_periods maps the disposal date to. Layer 6 of
   gold_fully_consolidated_tb reads that model instead of this one.

   Nothing else provides anything this model did, so it yields no rows. The
   column list is kept so that the PRD-12 tests still reading it
   (assert_disposal_gain_loss_exists, assert_cta_recycled_on_disposal) keep
   compiling until they are retargeted at the disposal journal; on a stack
   whose Ownership Periods carry is_disposal = 1 they flag every such row
   until then. It can be deleted once nothing refers to it. #}

select
    '' as consolidation_group,
    '' as data_area_id,
    toUInt16(0) as fiscal_year,
    toUInt8(0) as fiscal_period,
    toFloat64(0) as disposal_price,
    toFloat64(0) as net_assets,
    toFloat64(0) as ownership_pct,
    toFloat64(0) as remaining_goodwill,
    toFloat64(0) as gain_loss_amount,
    '' as adjustment_type,
    toDate('1970-01-01') as disposal_date
where 0
