-- Test: Entity layer in fully_consolidated_tb should tie to consolidated_trial_balance
-- Sum of entity-layer amounts in FCTB must equal sum in consolidated TB
select
    fctb.consolidation_group,
    fctb.fiscal_year,
    fctb.fiscal_period,
    fctb.main_account,
    sum(fctb.amount) as fctb_entity_amount,
    sum(ctb.group_amount) as ctb_group_amount,
    abs(sum(fctb.amount) - sum(ctb.group_amount)) as gap
from (
    select consolidation_group, fiscal_year, fiscal_period, main_account,
           sum(amount) as amount
    from {{ ref('gold_fully_consolidated_tb') }}
    where adjustment_type = 'entity'
    group by consolidation_group, fiscal_year, fiscal_period, main_account
) as fctb
inner join (
    select consolidation_group, fiscal_year, fiscal_period, main_account,
           sum(group_amount) as group_amount
    from {{ ref('gold_consolidated_trial_balance') }}
    group by consolidation_group, fiscal_year, fiscal_period, main_account
) as ctb
    on fctb.consolidation_group = ctb.consolidation_group
    and fctb.fiscal_year = ctb.fiscal_year
    and fctb.fiscal_period = ctb.fiscal_period
    and fctb.main_account = ctb.main_account
group by fctb.consolidation_group, fctb.fiscal_year, fctb.fiscal_period, fctb.main_account
having abs(sum(fctb.amount) - sum(ctb.group_amount)) > 0.01
