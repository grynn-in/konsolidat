{{ config(severity='warn') }}

{#
    konsol#117 pair 2 K3 (konsolidat#204 option (a); Deepak Pai, 8 Nov 2026).
    Replaces assert_ic_nci_account_declared (konsolidat#208), which named the
    groups whose intercompany NCI legs sat on the 'NCI' placeholder. Those
    legs are retired: intercompany eliminations are posted in full.

    What still needs the account: the minority's share of a partly owned
    subsidiary is one NCI line (the NCI movement schedule, konsol#117 pair 2
    K2) and the deal journals post to it too. A group that consolidates at
    least one entity by the full method at less than 100% effective ownership
    (gold_entity_ownership) must declare nci_account on its Consolidation
    Group root. Without it the NCI line has no home.

    One row per such group whose root declares none (or has no root row).
    A warning, not an error: nothing is posted to a wrong account, the
    report just cannot show the minority's share until the group declares it.
#}

with group_nci as (
    {{ ic_group_nci_accounts() }}
),

partial_subs as (
    select consolidation_group, count() as partly_owned_entities
    from {{ ref('gold_entity_ownership') }}
    where consolidation_method = 'full'
      and has_complete_chain = 1
      and effective_ownership_pct < 1 - 0.000001
    group by consolidation_group
)

select
    p.consolidation_group as consolidation_group,
    p.partly_owned_entities as partly_owned_entities
from partial_subs as p
left join group_nci as gn
    on gn.nci_group = p.consolidation_group
where gn.declared_nci_account = ''
