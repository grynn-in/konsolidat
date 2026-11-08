-- konsol#117 pair 2 K2 (konsolidat#204 option (a), IFRS 10.B94): each line of the NCI attribution journal
-- posted for a partly owned full-method subsidiary equals the minority's share of its result and CTA.
--
-- Oracle, built from the consolidated TB rows and never from the journal's own CTEs or from
-- gold_fx_revaluation. Per (group, entity, FY, period), with m = 1 - effective_ownership_pct:
--     P   = sum of translated P&L, year-end close rows excluded (gold_trial_balance_by_partner.
--           is_year_end_close, by account, as gold_equity_method_associates does)
--     A   = sum of translated amounts of ALL the entity's rows (the CTA plug restores the entity to
--           zero, so plug = -A)
--     retained-earnings line  expected = -m x P
--     CTA line                expected = +m x A          (= -m x plug)
--     NCI line                expected = -(RE line + CTA line) = m x (P - A), on the declared nci_account
-- Each line is compared on its own (konsol#117 pair 2 review, finding 8a): the former
-- assert_nci_attribution_balances could not fail, because the NCI line is built as the sum of the other
-- two. Here a wrong RE line or a wrong CTA line fails even when the journal still sums to zero. One row
-- per entity-period, naming the lines that differ.
--
-- A missing journal where an expected figure is non-zero flags too: that is how a chart without a
-- retained-earnings account, or a group whose root declares no nci_account, is named. That cause is
-- ALSO named, once per group, by assert_nci_account_declared_for_partial_subs (error): the same cause
-- twice is accepted, the group row says why, this row says which entity-period and how much. Rows the
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
            * sumIf(toFloat64(ctb.translated_amount),
                    ctb.is_pnl = 1
                    and (ctb.data_area_id, ctb.fiscal_year, ctb.fiscal_period, ctb.main_account)
                        not in (select data_area_id, fiscal_year, fiscal_period, main_account from close_keys))
            as pnl_share,
        (1.0 - eo.effective_ownership_pct) * sum(toFloat64(ctb.translated_amount)) as all_share
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
           -pnl_share as expected_re,
           all_share as expected_cta,
           pnl_share - all_share as expected_nci,
           0.0 as actual_re, 0.0 as actual_cta, 0.0 as actual_nci
    from expected
    union all
    select j.consolidation_group, j.data_area_id, j.fiscal_year, j.fiscal_period,
           0.0, 0.0, 0.0,
           sumIf(toFloat64(j.amount), j.account_role = 'retained_earnings'),
           sumIf(toFloat64(j.amount), j.account_role = 'cta'),
           sumIf(toFloat64(j.amount), j.account_role = 'nci'
                 and (j.consolidation_group, j.main_account) in
                     (select nci_group, declared_nci_account from nci_accounts))
    from {{ ref('gold_nci_attribution_journal') }} as j
    group by j.consolidation_group, j.data_area_id, j.fiscal_year, j.fiscal_period
)

select
    consolidation_group,
    data_area_id,
    fiscal_year,
    fiscal_period,
    sum(expected_re) as expected_re_total,
    sum(actual_re) as actual_re_total,
    sum(expected_cta) as expected_cta_total,
    sum(actual_cta) as actual_cta_total,
    sum(expected_nci) as expected_nci_total,
    sum(actual_nci) as actual_nci_total
from compared
group by consolidation_group, data_area_id, fiscal_year, fiscal_period
having abs(sum(expected_re) - sum(actual_re)) > 0.01
    or abs(sum(expected_cta) - sum(actual_cta)) > 0.01
    or abs(sum(expected_nci) - sum(actual_nci)) > 0.01
