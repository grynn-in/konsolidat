{#
    PRD-22: no consolidation layer the models computed is lost on its way into
    gold_fully_consolidated_tb, and none appears there without its source.

    Decided by Deepak Pai, 6 Oct 2026: konsolidat#238 option #238-4, at error
    severity. It supersedes #238-1, which conditioned the layers on
    declarations (Published IC accounts, partner membership, more than one
    currency). A review of PR #261 measured that this did not match the
    models: an unmatched IC pair, with no ic_difference_account, is
    eliminated by nothing, and CTA does not depend on how many currencies
    the group has. Whether an elimination SHOULD exist stays with
    gold_ic_reconciliation and gold_ic_unmatched. Rejected: #238-1 as worded,
    and #238-2 (warn and keep asserting all four).

    A layer must appear for a group exactly when its source model has rows for
    that group. Each source is mapped to the adjustment_type
    gold_fully_consolidated_tb gives it:
      - entity:              gold_consolidated_trial_balance (layer 1);
      - ic_elimination:      gold_ic_eliminations, elimination_view 'group' (layer 2).
                             The 'nci' kind lands as ic_elimination_nci. Every
                             other kind, including unrealized_profit from
                             ic_elimination_rules, lands as ic_elimination.
                             NCI-view rows never enter the consolidated TB;
      - topside:             gold_consolidation_adjustments, adjustment_type
                             'topside' (layer 4 passes adjustment_type through);
      - cta:                 gold_fx_revaluation (layer 3).
    Every model carries the group in consolidation_group.

    Two directions, one row per (group, layer):
      - missing_layer: the source has rows, the consolidated TB has none;
      - unexpected_layer: the consolidated TB has the layer, the source has no
        rows (a stale or misattributed layer).

    konsolidat#238 / #249: NOT IN, not a LEFT JOIN. adjustment_type is a
    String, and under join_use_nulls = 0 (the server default; a singular test
    carries no settings clause) an unmatched LEFT JOIN fills it with '' rather
    than NULL. The former `where actual.layer is null` therefore matched
    nothing, and the test could never fail.
#}

with expected as (

    select distinct consolidation_group, 'entity' as layer
    from {{ ref('gold_consolidated_trial_balance') }}

    union all

    select distinct
        consolidation_group,
        if(elimination_kind = 'nci', 'ic_elimination_nci', 'ic_elimination') as layer
    from {{ ref('gold_ic_eliminations') }}
    where elimination_view = 'group'

    union all

    select distinct consolidation_group, 'topside' as layer
    from {{ ref('gold_consolidation_adjustments') }}
    where adjustment_type = 'topside'

    union all

    select distinct consolidation_group, 'cta' as layer
    from {{ ref('gold_fx_revaluation') }}

),

actual as (
    select distinct consolidation_group, adjustment_type as layer
    from {{ ref('gold_fully_consolidated_tb') }}
    where adjustment_type in ('entity', 'ic_elimination', 'ic_elimination_nci', 'topside', 'cta')
)

select 'missing_layer' as error, consolidation_group, layer
from expected
where (consolidation_group, layer) not in (select consolidation_group, layer from actual)

union all

select 'unexpected_layer' as error, consolidation_group, layer
from actual
where (consolidation_group, layer) not in (select consolidation_group, layer from expected)
