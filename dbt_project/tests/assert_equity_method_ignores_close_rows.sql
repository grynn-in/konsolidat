-- PRD-14 / konsolidat#279 defect 3: an associate's result for a period is its OWN activity there,
-- never the year-end close silver_tb_movements synthesizes in the Closing period (konsolidat#259).
-- The close moves the year's P&L into retained earnings, so read as "net income of P13" it posts an
-- equity-method entry equal and opposite to the year's result. The marker is
-- gold_trial_balance_by_partner.is_year_end_close (posting_layer 'Year-end close' in silver_gl_entries),
-- the one gold_consolidated_trial_balance reads.
--
-- Oracle: for every equity associate period, EQ_INCOME must equal the PRE-CLOSE P&L movement
-- (close rows excluded) x effective ownership x the governed Average rate (1.0 in the same currency;
-- a Closing-type period reads its year's last Regular period, rate_period_map()). A share of 0.01 or
-- less posts no journal, so it is expected as 0. A Closing period with no activity of its own is
-- therefore expected as no journal at all. Built from the model's inputs, never from its CTEs.
-- Fixture: dbt_project/test_fixtures/assert_equity_method_ignores_close_rows.sql.
{{ config(severity='error') }}
with expected as (
    select
        eo.consolidation_group as consolidation_group,
        tb.data_area_id as data_area_id,
        tb.fiscal_year as fiscal_year,
        tb.fiscal_period as fiscal_period,
        sum(tb.period_net_amount) * eo.effective_ownership_pct
            * if(ec.accounting_currency = grp.reporting_currency, 1.0, any(toFloat64(r.rate))) as expected_amount
    from {{ ref('gold_trial_balance_by_partner') }} as tb
    inner join {{ ref('silver_main_accounts') }} as ma
        on tb.main_account = ma.main_account_id
    inner join {{ ref('gold_entity_ownership') }} as eo
        on tb.data_area_id = eo.data_area_id
        and tb.fiscal_year = eo.fiscal_year
        and tb.fiscal_period = eo.fiscal_period
    inner join {{ ref('silver_entity_currencies') }} as ec
        on ec.data_area_id = tb.data_area_id
    inner join {{ source('epm_gold', 'consolidation_groups') }} as grp
        on grp.consolidation_group = eo.consolidation_group
        and grp.data_area_id = ''
    left join {{ rate_period_map() }} as rpm
        on rpm.fiscal_year = tb.fiscal_year
        and rpm.fiscal_period = tb.fiscal_period
    left join {{ source('epm_staging', 'group_exchange_rates') }} as r
        on r.rate_type = 'Average'
        and r.from_currency = ec.accounting_currency
        and r.to_currency = grp.reporting_currency
        and r.fiscal_year = if(rpm.mapped = 1, rpm.rate_year, toUInt16(tb.fiscal_year))
        and r.fiscal_period = if(rpm.mapped = 1, rpm.rate_period, toUInt16(tb.fiscal_period))
    where eo.consolidation_method = 'equity'
      and eo.has_complete_chain = 1
      and ma.is_pnl = 1
      and tb.is_year_end_close = 0
    group by eo.consolidation_group, tb.data_area_id, tb.fiscal_year, tb.fiscal_period,
             eo.effective_ownership_pct, ec.accounting_currency, grp.reporting_currency
),

compared as (
    select consolidation_group, data_area_id, fiscal_year, fiscal_period,
           if(abs(expected_amount) > 0.01, expected_amount, 0.0) as expected_amount,
           0.0 as actual_amount
    from expected
    union all
    select consolidation_group, data_area_id, fiscal_year, fiscal_period,
           0.0 as expected_amount,
           toFloat64(amount) as actual_amount
    from {{ ref('gold_equity_method_associates') }}
    where main_account = 'EQ_INCOME'
)

select
    consolidation_group,
    data_area_id,
    fiscal_year,
    fiscal_period,
    sum(expected_amount) as expected_total,
    sum(actual_amount) as actual_total
from compared
group by consolidation_group, data_area_id, fiscal_year, fiscal_period
having abs(sum(expected_amount) - sum(actual_amount)) > 0.01
