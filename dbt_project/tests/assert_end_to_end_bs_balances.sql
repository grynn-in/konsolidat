-- PRD-22 Test: End-to-end BS must balance (total debits ≈ total credits)
-- across all layers in the fully consolidated TB
select
    consolidation_group,
    fiscal_year,
    fiscal_period,
    sum(amount) as net_balance
from {{ ref('gold_fully_consolidated_tb') }}
inner join {{ ref('silver_main_accounts') }} as ma
    on {{ ref('gold_fully_consolidated_tb') }}.main_account = ma.main_account_id
where ma.is_balance_sheet = 1
group by consolidation_group, fiscal_year, fiscal_period
having abs(sum(amount)) > 1.00
