{#
    PRD-14: equity-method entities must be excluded from IC eliminations.

    F2: the method is dated and per-group, so the check is keyed on
    (group, period). It read the consolidation_groups seed, which carried one
    method per entity for all time and nothing about the chain — an entity can
    be line-consolidated into its own sub-group and equity-method at the parent.
    Same strictness as before: an elimination raised in a group holding an
    equity-method entity in that period is a failure.
#}
select
    ie.rule_id,
    ie.consolidation_group,
    ie.fiscal_year,
    ie.fiscal_period,
    ie.debit_account,
    ie.credit_account
from {{ ref('gold_ic_eliminations') }} as ie
inner join {{ ref('gold_entity_ownership') }} as eo
    on ie.consolidation_group = eo.consolidation_group
    and ie.fiscal_year = eo.fiscal_year
    and ie.fiscal_period = eo.fiscal_period
where eo.consolidation_method = 'equity'
limit 10
