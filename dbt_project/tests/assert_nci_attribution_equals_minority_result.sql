-- konsol#117 pair 2 K2 (konsolidat#204 option (a), IFRS 10.B94): the NCI line posted for a partly
-- owned full-method subsidiary equals the minority's share of its result and CTA.
--
-- Oracle, built from the consolidated TB rows and never from the journal's own CTEs or from
-- gold_fx_revaluation: per (group, entity, FY, period),
--     expected = (1 - effective_ownership_pct) x (sum of translated P&L, year-end close rows excluded
--                                                 + the CTA plug)
-- where the CTA plug is minus the sum of translated amounts of ALL the entity's rows (the plug
-- restores the entity to zero). The year-end close (konsolidat#259, gold_trial_balance_by_partner.
-- is_year_end_close) is excluded by account, as gold_equity_method_associates does: a key's close
-- rows are never mixed with activity in one period.
--
-- A missing journal where the expected figure is non-zero flags too: that is how a chart without a
-- retained-earnings account, or a group whose root declares no nci_account, is named. Rows the
-- model does not attribute (method other than full, ownership 1, incomplete chain) are not expected.
-- Fixture: dbt_project/test_fixtures/nci_attribution_journal.sql (+ .no_nci_account.must_flag).
{{ config(severity='error') }}
with close_keys as (
    select distinct data_area_id, fiscal_year, fiscal_period, main_account
    from {{ ref('gold_trial_balance_by_partner') }}
    where is_year_end_close = 1
),

nci_accounts as (
    {{ ic_group_nci_accounts() }}
),

expected as (
    select
        eo.consolidation_group as consolidation_group,
        eo.data_area_id as data_area_id,
        eo.fiscal_year as fiscal_year,
        eo.fiscal_period as fiscal_period,
        (1.0 - eo.effective_ownership_pct)
            * (sumIf(toFloat64(ctb.translated_amount),
                     ctb.is_pnl = 1
                     and (ctb.data_area_id, ctb.fiscal_year, ctb.fiscal_period, ctb.main_account)
                         not in (select data_area_id, fiscal_year, fiscal_period, main_account from close_keys))
               - sum(toFloat64(ctb.translated_amount))) as expected_amount
    from {{ ref('gold_entity_ownership') }} as eo
    inner join {{ ref('gold_consolidated_trial_balance') }} as ctb
        on ctb.consolidation_group = eo.consolidation_group
        and ctb.data_area_id = eo.data_area_id
        and ctb.fiscal_year = eo.fiscal_year
        and ctb.fiscal_period = eo.fiscal_period
    where eo.consolidation_method = 'full'
      and eo.has_complete_chain = 1
      and eo.effective_ownership_pct < 1 - 0.000001
    group by eo.consolidation_group, eo.data_area_id, eo.fiscal_year, eo.fiscal_period,
             eo.effective_ownership_pct
),

compared as (
    select consolidation_group, data_area_id, fiscal_year, fiscal_period,
           expected_amount, 0.0 as actual_amount
    from expected
    union all
    select j.consolidation_group, j.data_area_id, j.fiscal_year, j.fiscal_period,
           0.0 as expected_amount, toFloat64(j.amount) as actual_amount
    from {{ ref('gold_nci_attribution_journal') }} as j
    where (j.consolidation_group, j.main_account) in
          (select nci_group, declared_nci_account from nci_accounts)
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
