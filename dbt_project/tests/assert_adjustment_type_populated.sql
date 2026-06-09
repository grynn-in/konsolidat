-- PRD-5 Test: Every row in fully consolidated TB must have an adjustment_type
select
    consolidation_group,
    data_area_id,
    fiscal_year,
    fiscal_period,
    main_account
from {{ ref('gold_fully_consolidated_tb') }}
where adjustment_type is null
   or adjustment_type = ''
