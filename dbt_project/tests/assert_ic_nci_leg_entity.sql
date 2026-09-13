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

{% set nci = ic_nci_account() %}

with entries as (
    select
        consolidation_group, fiscal_year, fiscal_period, elimination_view, elimination_kind,
        entity_a, account_a, entity_b, account_b,
        debit_account, debit_entity, credit_account, credit_entity,
        toUInt8(debit_account = '{{ nci }}') + toUInt8(credit_account = '{{ nci }}') as nci_legs,
        if(debit_account = '{{ nci }}', credit_account, debit_account) as side_account,
        if(debit_account = '{{ nci }}', credit_entity, debit_entity) as side_entity,
        if(debit_account = '{{ nci }}', debit_entity, credit_entity) as nci_entity
    from {{ ref('gold_ic_eliminations') }}
    where rule_type = 'balance'
      and ((elimination_view = 'group' and elimination_kind = 'nci')
           or (elimination_view = 'nci' and elimination_kind = 'matched'))
)

select *
from entries
where nci_legs != 1
   or not ((side_account = account_a and side_entity = entity_a)
           or (side_account = account_b and side_entity = entity_b))
   or nci_entity != if(elimination_view = 'nci', side_entity,
                       if(side_entity = entity_a, entity_b, entity_a))
