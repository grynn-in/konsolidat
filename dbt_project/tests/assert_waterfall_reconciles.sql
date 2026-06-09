-- PRD-22 Test: Waterfall final_amount must equal sum of all layers
select
    consolidation_group,
    fiscal_year,
    fiscal_period,
    final_amount,
    entity_amount + ic_elimination_amount + cta_amount + topside_amount
        + equity_method_amount + acq_disposal_amount as calculated_total,
    abs(final_amount - (entity_amount + ic_elimination_amount + cta_amount + topside_amount
        + equity_method_amount + acq_disposal_amount)) as gap
from {{ ref('gold_consolidation_waterfall') }}
where abs(final_amount - (entity_amount + ic_elimination_amount + cta_amount + topside_amount
    + equity_method_amount + acq_disposal_amount)) > 0.01
