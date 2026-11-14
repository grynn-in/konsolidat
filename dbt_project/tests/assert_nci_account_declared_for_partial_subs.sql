{{ config(severity='error') }}

{#
    konsol#117 pair 2 K3 (konsolidat#204 option (a); Deepak Pai, 8 Nov 2026).
    Replaces assert_ic_nci_account_declared (konsolidat#208), which named the
    groups whose intercompany NCI legs sat on the 'NCI' placeholder. Those
    legs are retired: intercompany eliminations are posted in full.

    What still needs two homes: the minority's share of a partly owned
    subsidiary is one NCI line on the group's nci_account and a debit or credit
    to retained earnings (gold_nci_attribution_journal, konsol#117 pair 2 K2),
    and the deal journals post to the NCI account too. A group that
    consolidates at least one entity by the full method at less than 100%
    effective ownership (gold_entity_ownership) must therefore have
      (1) nci_account declared on its Consolidation Group root, and
      (2) a retained-earnings account in the chart
          (silver_main_accounts.is_retained_earnings = 1).

    ERROR, not a warning (review fix, konsol#117 pair 2 finding 9): without
    either, the attribution journal cannot post (it inner-joins both), the
    minority's share is missing from the consolidated trial balance, and
    assert_nci_attribution_equals_minority_result stops the build for the same
    cause. This test names the cause once per group; that one names it again
    per entity-period with the amount. Both are errors on purpose: the build
    stops either way, and the group row here says WHY.

    One row per such group, with the reason(s): 'no nci_account on the root
    row' and/or 'no retained-earnings account in the chart'.
    Fixtures: test_fixtures/assert_nci_account_declared_for_partial_subs
    (.no_account.must_flag, .no_retained_earnings.must_flag).
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
),

chart as (
    select countIf(is_retained_earnings = 1) as retained_earnings_accounts
    from {{ ref('silver_main_accounts') }}
)

select
    p.consolidation_group as consolidation_group,
    p.partly_owned_entities as partly_owned_entities,
    arrayStringConcat(arrayFilter(x -> x != '', [
        if(gn.declared_nci_account = '', 'no nci_account on the root row', ''),
        if(c.retained_earnings_accounts = 0, 'no retained-earnings account in the chart', '')
    ]), '; ') as reason,
    concat('group ', p.consolidation_group, ' has ', toString(p.partly_owned_entities),
           ' partly owned full-method entities and the build stops: the NCI attribution journal cannot post (',
           arrayStringConcat(arrayFilter(x -> x != '', [
               if(gn.declared_nci_account = '', 'no nci_account on the root row', ''),
               if(c.retained_earnings_accounts = 0, 'no retained-earnings account in the chart', '')
           ]), '; '),
           ').') as problem
from partial_subs as p
left join group_nci as gn
    on gn.nci_group = p.consolidation_group
cross join chart as c
where gn.declared_nci_account = '' or c.retained_earnings_accounts = 0
