-- konsol#305-D2-2 / D2-11 (batch review 27 Sep finding 1): an auto_reversal
-- row must net to exactly minus its original line, not merely exist in the
-- right period (assert_auto_reversal_generated only checks presence).
-- Key a line by (consolidation_group, journal_id, data_area_id, main_account);
-- sum net_amount per key, split between the auto_reversal rows and the rest.
-- Only journals that have a reversal are compared (inner join): a journal
-- with no reversal has no row in `reversals` and is silently skipped, never
-- a LEFT JOIN ... IS NULL (konsolidat#249).
with reversals as (
    select
        consolidation_group, journal_id, data_area_id, main_account,
        sum(net_amount) as reversal_net
    from {{ ref('gold_consolidation_adjustments') }}
    where adjustment_type = 'auto_reversal'
    group by consolidation_group, journal_id, data_area_id, main_account
),

originals as (
    select
        consolidation_group, journal_id, data_area_id, main_account,
        sum(net_amount) as original_net
    from {{ ref('gold_consolidation_adjustments') }}
    where adjustment_type != 'auto_reversal'
    group by consolidation_group, journal_id, data_area_id, main_account
)

select
    r.consolidation_group, r.journal_id, r.data_area_id, r.main_account,
    r.reversal_net, o.original_net
from reversals as r
inner join originals as o
    on r.consolidation_group = o.consolidation_group
   and r.journal_id = o.journal_id
   and r.data_area_id = o.data_area_id
   and r.main_account = o.main_account
where round(r.reversal_net, 2) != round(-o.original_net, 2)
