{{
    config(
        materialized='view',
        schema='gold'
    )
}}

{# K.EPM-queryable shape for the GROUP-level consolidated trial balance.

   gold_fully_consolidated_tb carries entity rows + consolidation adjustment
   rows (CTA, IC eliminations, topside, NCI) per consolidation_group. This view
   rolls them up to the group and renames the group into the entity slot the
   epm_batch query builder expects, exposing one consolidated (post-FX,
   post-elimination) signed amount per account/period:

     entity  arg  -> data_area_id = consolidation_group   (e.g. GROUP_CORP)
     account arg  -> main_account                          (real GL account)
     measure      -> consolidated_amount

   Serves both consolidated P&L and Balance Sheet — the account chosen in the
   sheet decides which statement. Registered as Fact Table `consolidated` so
   =K.EPM("GROUP_CORP", 2024, 6, "510500", "consolidated_amount", "consolidated")
   reads the group figure live (companion to entity-level actuals via K.EPM and
   the cash flow via gold_cashflow_fact / K.CF). #}

select
    consolidation_group as data_area_id,
    fiscal_year,
    fiscal_period,
    main_account,
    sum(coalesce(amount, 0)) as consolidated_amount
from {{ ref('gold_fully_consolidated_tb') }}
group by
    consolidation_group,
    fiscal_year,
    fiscal_period,
    main_account
