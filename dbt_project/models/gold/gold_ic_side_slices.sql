{{
    config(
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# konsolidat#245 option D, layer 2's mechanism (option C, Deepak Pai, 6 Oct
   2026): what each intercompany SIDE booked, per declared dimension value.

   gold_ic_eliminations splits each elimination leg across its own side's
   slices using this, so an elimination carries the slice it eliminates.

   WHY THIS IS A SEPARATE MODEL, and not extra columns on
   gold_ic_reconciliation. Putting the dimensions into that model's pair key
   would break matching: a receivable in A tagged dim_cost_center = 'CC1' and
   the matching payable in B tagged 'CC2' become two different pairs, each with
   a zero counterparty. The intercompany difference would stop matching and the
   consolidated trial balance would still balance perfectly — numbers moving
   while nothing looks wrong. gold_ic_reconciliation also has sixteen consumers
   (six models, ten singular tests), so its grain is the last thing in this
   chain that should change. This model is purely additive: nothing that exists
   reads it, so nothing that exists can move because of it.

   The grain is gold_ic_reconciliation's `sides` CTE PLUS the declared
   dimensions — same source, same filters, same join — so a side's slices sum
   to exactly the movement that CTE reports for it. That identity is what makes
   the split in gold_ic_eliminations exact rather than an allocation, and
   assert_ic_side_slices_sum_to_the_side asserts it.

   A dimension a site has not declared contributes no column (var('dimensions')
   is the declared set), so on a site with none this model is one row per side
   and the split is a no-op. #}

with ic_accounts as (
    {{ ic_account_map() }}
)

select
    ctb.consolidation_group as consolidation_group,
    ctb.fiscal_year as fiscal_year,
    ctb.fiscal_period as fiscal_period,
    ctb.data_area_id as entity,
    ctb.partner_data_area_id as partner,
    ctb.main_account as account,
    ica.counterpart as counterpart,
    {{ dim_select('ctb.', trailing=true) }}
    ifNull(toFloat64(sum(ctb.local_amount)), 0) as mov_local,
    ifNull(toFloat64(sum(ctb.translated_amount)), 0) as mov_translated,
    ifNull(toFloat64(sum(ctb.group_amount)), 0) as mov_group
from {{ ref('gold_consolidated_trial_balance') }} as ctb
inner join ic_accounts as ica
    on ctb.main_account = ica.account
where ctb.partner_data_area_id != ''
  and ctb.partner_data_area_id != ctb.data_area_id
group by
    ctb.consolidation_group,
    ctb.fiscal_year,
    ctb.fiscal_period,
    ctb.data_area_id,
    ctb.partner_data_area_id,
    ctb.main_account,
    ica.counterpart
    {{ dim_group_by('ctb.', leading=true) }}
