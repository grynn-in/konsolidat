{#
    #175 third review L2: an NCI-line leg is attributed to the entity whose
    minority owners hold it.

    - Group view, 'nci': one leg takes a pair side (its account and entity)
      down to the share the other side is held at; the other leg is on the
      NCI line, attributed to the OTHER side's entity, the partly owned one.
    - NCI view, 'matched': one leg eliminates a side's minority share; the
      other is on the NCI line, attributed to that same side's entity.

    Each entry has exactly one NCI leg, and its other leg is one of the
    pair's two sides.
#}

{# The NCI line is the group's own: its declared NCI Account, or the
   placeholder (konsolidat#208), resolved as gold_ic_eliminations does. #}
with group_nci as (
    {{ ic_group_nci_accounts() }}
),

nci_entries as (
    select
        e.consolidation_group as consolidation_group, e.fiscal_year as fiscal_year,
        e.fiscal_period as fiscal_period, e.elimination_view as elimination_view,
        e.elimination_kind as elimination_kind,
        e.entity_a as entity_a, e.account_a as account_a, e.entity_b as entity_b, e.account_b as account_b,
        e.debit_account as debit_account, e.debit_entity as debit_entity,
        e.credit_account as credit_account, e.credit_entity as credit_entity,
        {{ ic_nci_account_or_placeholder('gn.declared_nci_account') }} as nci_account
    from {{ ref('gold_ic_eliminations') }} as e
    left join group_nci as gn on gn.nci_group = e.consolidation_group
    where e.rule_type = 'balance'
      and ((e.elimination_view = 'group' and e.elimination_kind = 'nci')
           or (e.elimination_view = 'nci' and e.elimination_kind = 'matched'))
),

entries as (
    select
        *,
        toUInt8(debit_account = nci_account) + toUInt8(credit_account = nci_account) as nci_legs,
        if(debit_account = nci_account, credit_account, debit_account) as side_account,
        if(debit_account = nci_account, credit_entity, debit_entity) as side_entity,
        if(debit_account = nci_account, debit_entity, credit_entity) as nci_entity
    from nci_entries
)

select *
from entries
where nci_legs != 1
   or not ((side_account = account_a and side_entity = entity_a)
           or (side_account = account_b and side_entity = entity_b))
   or nci_entity != if(elimination_view = 'nci', side_entity,
                       if(side_entity = entity_a, entity_b, entity_a))
