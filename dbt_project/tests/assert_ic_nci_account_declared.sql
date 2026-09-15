{{ config(severity='warn') }}

{#
    konsolidat#208: a group's intercompany NCI line posts to the NCI Account
    it declares on its Consolidation Group root (nci_account). Until it
    declares one, gold_ic_eliminations posts the line to
    ic_nci_placeholder(), a pseudo-account no chart holds, so no report shows
    the minority's share of the eliminated balances.

    One row per group whose NCI lines are on the placeholder: its root
    declares no nci_account (or it has no root row). A warning, not an
    error: the eliminations still net to zero.

    NCI lines are the group view's 'nci' entries and the NCI view's
    'matched' entries (gold_ic_eliminations' elimination_view and
    elimination_kind), each with one leg on the NCI line.
#}

select
    consolidation_group,
    count() as nci_lines
from {{ ref('gold_ic_eliminations') }}
where rule_type = 'balance'
  and ((elimination_view = 'group' and elimination_kind = 'nci')
       or (elimination_view = 'nci' and elimination_kind = 'matched'))
  and (debit_account = {{ ic_nci_placeholder() }} or credit_account = {{ ic_nci_placeholder() }})
group by consolidation_group
