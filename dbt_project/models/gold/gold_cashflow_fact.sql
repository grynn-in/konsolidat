{{
    config(
        materialized='view',
        schema='gold'
    )
}}

{# K.EPM-queryable shape for the consolidated cash flow.

   epm_batch's query builder filters on the fixed key columns
   (data_area_id, fiscal_year, main_account) and sums a measure. The
   consolidated cash flow is keyed by (consolidation_group, cf_line_item)
   instead, so this thin view renames those into the slots the builder
   expects — no query-builder change needed:

     entity  arg  -> data_area_id  = consolidation_group   (e.g. GROUP_CORP)
     account arg  -> main_account  = cf_line_item           (e.g. "Change in Inventory")
     measure      -> cash_flow_amount

   Registered as Dataset `cashflow` so =K.EPM("GROUP_CORP", 2024, 6,
   "Change in Inventory", "cash_flow_amount", "cashflow") — and the K.CF()
   wrapper — read it live. #}

select
    consolidation_group as data_area_id,
    fiscal_year,
    fiscal_period,
    cf_category,
    cf_line_item        as main_account,
    sum(cash_flow_amount) as cash_flow_amount
from {{ ref('gold_consolidated_cash_flow') }}
group by
    consolidation_group,
    fiscal_year,
    fiscal_period,
    cf_category,
    cf_line_item
