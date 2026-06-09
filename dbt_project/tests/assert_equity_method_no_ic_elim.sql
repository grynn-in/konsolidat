-- PRD-14 Test: Equity-method entities must be excluded from IC eliminations
select
    ie.rule_id,
    ie.consolidation_group,
    ie.debit_account,
    ie.credit_account
from {{ ref('gold_ic_eliminations') }} as ie
inner join {{ ref('consolidation_groups') }} as cg
    on (ie.consolidation_group = cg.consolidation_group)
where cg.consolidation_method = 'equity'
limit 10
