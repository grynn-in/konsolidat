-- PRD-22 Test: Waterfall final_amount must equal sum of all layers
-- The bucket sum loops over waterfall_buckets() (macros/waterfall_buckets.sql), so a new bucket is reconciled
-- without editing this test (#357 review F4).
{% set bucket_sum %}{% for bucket in waterfall_buckets().keys() %}{{ bucket }}_amount{{ ' + ' if not loop.last }}{% endfor %}{% endset %}
select
    consolidation_group,
    fiscal_year,
    fiscal_period,
    final_amount,
    {{ bucket_sum }} as calculated_total,
    abs(final_amount - ({{ bucket_sum }})) as gap
from {{ ref('gold_consolidation_waterfall') }}
where abs(final_amount - ({{ bucket_sum }})) > 0.01
