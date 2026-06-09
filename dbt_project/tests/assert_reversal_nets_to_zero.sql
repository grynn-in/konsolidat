-- PRD-16 Test: Original + reversal entries must net to zero per journal_id group
select
    base_journal_id,
    sum(net_amount) as total_net
from (
    select
        coalesce(nullIf(reversal_journal_id, ''), journal_id) as base_journal_id,
        net_amount
    from {{ ref('gold_consolidation_adjustments') }}
    where reversal_journal_id != '' or journal_id in (
        select reversal_journal_id from {{ ref('gold_consolidation_adjustments') }}
        where reversal_journal_id != ''
    )
) as paired
group by base_journal_id
having abs(sum(net_amount)) > 0.01
