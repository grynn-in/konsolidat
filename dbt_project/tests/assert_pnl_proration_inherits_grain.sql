{# konsolidat#171 step 2c review F1: the partial-period P&L proration inherits the dimension grain of its source.
   Decided by Deepak Pai, 3 Oct 2026 (consolidation entry dimensions are hybrid: inherit where derivable,
   declare on journal lines, blank only on deal journals). gold_acquisition_adjustments is not a deal journal and
   its source, gold_consolidated_trial_balance, carries a dimension value on every row, so its rows must too.
   Without that, a dimension report shows the full-period P&L per member and one blank-dimension negative lump.

   Read from gold_fully_consolidated_tb (the layer a report reads), so the test judges what a report sees.
   Faults, one row each:
     grain not in the trial balance   a pnl_proration row on a P&L account sits on a dimension grain that
                                      gold_consolidated_trial_balance does not have for that entity, period and
                                      account (the blank lump)
     dimension grain unbalanced       the pnl_proration rows of a (group, entity, year, period, dimensions) do
                                      not sum to 0: the retained-earnings line must sit on the same dimensions as the
                                      P&L it balances
   Fixtures: assert_partial_period_pnl_matches_treatment.acquisition_pro_rate_dimensions.sql. #}
with proration as (
    select
        consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account,
        {{ dim_select(trailing=true) }}
        amount as line_amount
    from {{ ref('gold_fully_consolidated_tb') }}
    where adjustment_type = 'pnl_proration'
),

pnl_accounts as (
    select main_account_id from {{ ref('silver_main_accounts') }} where is_pnl = 1
),

source_grain as (
    select distinct
        consolidation_group, data_area_id, toUInt16(fiscal_year) as fiscal_year, toUInt16(fiscal_period) as fiscal_period,
        main_account{{ dim_select(leading=true) }}
    from {{ ref('gold_consolidated_trial_balance') }}
)

select
    'grain not in the trial balance' as fault,
    consolidation_group, data_area_id,
    toUInt16(fiscal_year) as fiscal_year, toUInt16(fiscal_period) as fiscal_period,
    main_account,
    toFloat64(line_amount) as amount
from proration
where main_account in (select main_account_id from pnl_accounts)
  and (consolidation_group, data_area_id, toUInt16(fiscal_year), toUInt16(fiscal_period), main_account{{ dim_select(leading=true) }})
      not in (select consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account{{ dim_select(leading=true) }} from source_grain)

union all

select
    'dimension grain unbalanced' as fault,
    consolidation_group, data_area_id,
    toUInt16(fiscal_year) as fiscal_year, toUInt16(fiscal_period) as fiscal_period,
    '' as main_account,
    toFloat64(sum(line_amount)) as amount
from proration
group by consolidation_group, data_area_id, fiscal_year, fiscal_period{{ dim_group_by(leading=true) }}
having abs(toFloat64(sum(line_amount))) > 0.01
