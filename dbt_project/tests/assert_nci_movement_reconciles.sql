-- PRD-13 Test: NCI movement — share of profit must be consistent with
-- the NCI amount from consolidated TB P&L entries
select
    nm.consolidation_group,
    nm.data_area_id,
    nm.fiscal_year,
    nm.fiscal_period,
    nm.share_of_profit,
    tb_nci.nci_total
from {{ ref('gold_nci_movement_schedule') }} as nm
inner join (
    select
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        sum(nci_amount) as nci_total
    from {{ ref('gold_consolidated_trial_balance') }}
    where is_pnl = 1
    group by consolidation_group, data_area_id, fiscal_year, fiscal_period
) as tb_nci
    on nm.consolidation_group = tb_nci.consolidation_group
    and nm.data_area_id = tb_nci.data_area_id
    and nm.fiscal_year = tb_nci.fiscal_year
    and nm.fiscal_period = tb_nci.fiscal_period
where abs(nm.share_of_profit - tb_nci.nci_total) > 0.01
