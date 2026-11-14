{{ config(severity='error') }}
{# konsolidat#316 7h: every adjustment_type gold_fully_consolidated_tb carries must
   sit in a gold_consolidation_waterfall bucket (macro waterfall_buckets), or the
   waterfall's final_amount holds value no column explains. Returns one row per
   type no bucket holds, so the next new layer is named when it lands. #}
select
    adjustment_type,
    count() as rows_in_tb
from {{ ref('gold_fully_consolidated_tb') }}
where adjustment_type not in ({{ "'" ~ waterfall_bucketed_types() | join("','") ~ "'" }})
group by adjustment_type
