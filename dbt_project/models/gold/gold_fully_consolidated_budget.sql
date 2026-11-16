{{
    config(
        materialized='table',
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# konsol#348 S4 (W6; S4-Q3 a, S4-Q4 a): the fully consolidated BUDGET, in the shape of
   gold_fully_consolidated_tb plus three grain columns (scenario_id, cycle, layer), over
   gold_consolidated_budget_tb. S5's readers read the same columns for a budget as for the
   actuals: (consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account,
   account_name, the budget dimensions, scenario_id, cycle, layer, reporting_currency, amount,
   adjustment_type, journal_id). The grain columns sit after the dimensions, where the core
   placed them in gold_consolidated_budget_tb. The dimensions are the budget dimensions
   (get_budget_dimensions(), the chart's in_budget subset, BUD-8-2), as in that model.

   Three layers, each a consolidation of its own per (scenario, cycle, layer): a layer's plug is
   never computed across another layer, Cycle or scenario (that would telescope two
   consolidations into one; assert_budget_consolidated_balances catches it).

   - 'entity'           sum(group_amount) per account and dimensions, as gold_fully_consolidated_tb's
                        layer 1. A budget has one row per key already (partner_data_area_id is ''
                        on every row), so the sum is over nothing but the key itself.
   - 'cta'              the residual, gold_fx_revaluation's formula verbatim: -sum(group_amount) over
                        ALL the entity's accounts of the period, one plug row per (group, entity,
                        period) and here per (scenario, cycle, layer), main_account the literal
                        'CTA', dimensions blank. A same-currency entity's residual is 0 and the row is
                        still emitted, as for the actuals. As for the actuals, this is the WHOLE
                        residual: a budget whose local rows do not themselves sum to zero (a
                        single-sided Budget Annual Input with no offsetting line) puts that local
                        imbalance into this plug too, translated at the closing rate; the test
                        cannot tell the two apart, and the Cycle's own entry rules are the place
                        that keeps a budget double-entry.
   - 'nci_attribution'  gold_nci_attribution_journal's formula: for a full-method subsidiary owned
                        below 100%, result_share = sum(nci_amount) over the period's P&L rows and
                        cta_share = (1 - ownership) x the entity's CTA plug; lines
                        retained-earnings -result_share, 'CTA' -cta_share, the group's nci_account
                        result_share + cta_share; a zero line is omitted, a journal whose two
                        shares are both 0 is omitted; no retained-earnings account in the chart or
                        no nci_account on the group's root means no journal (inner joins, as
                        there). What differs from the actuals' journal: ownership_pct and
                        consolidation_method are read from the budget rows themselves (the core
                        carries them from the budget's own ownership resolution, and already keeps
                        only has_complete_chain = 1 rows), not from gold_entity_ownership, whose
                        spine is the actuals' periods; and the year-end close exclusion is moot
                        (a budget posts no close rows, is_year_end_close is 0 throughout).
                        journal_id is 'NCI-{group}-{entity}-{FY}-P{period}-{scenario}-{cycle}-{layer}'.

   Absent, by decision:
   - 'ic_elimination' (konsol#427): a budget has no partner, so no intercompany pair exists to
     eliminate. This model is the budget BEFORE ELIMINATIONS, and every reader labels it so.
   - deal journals ('acquisition', 'goodwill_amortisation', 'disposal', 'pnl_proration'),
     'topside' and 'equity_method' (konsol#425): actuals-only journals with no scenario key.
   Within one (group, scenario, cycle, layer, entity, period) the three layers therefore sum to 0
   by construction (assert_budget_consolidated_balances, error).

   A table, rebuilt whole with gold_consolidated_budget_tb (S4-Q4 a): no orchestrator scope. Nothing
   here reads or is read by the close (gold_fully_consolidated_tb, the close fingerprint;
   tests/test_budget_outside_close.py pins it). #}

{# Layer 1: entity translated balances, at the account and dimension grain. #}
with entity_balances as (
    select
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        main_account,
        account_name,
        {{ dim_select(dims=get_budget_dimensions(), trailing=true) }}
        scenario_id,
        cycle,
        layer,
        reporting_currency,
        sum(group_amount) as amount,
        'entity' as adjustment_type,
        '' as journal_id
    from {{ ref('gold_consolidated_budget_tb') }}
    group by
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        main_account,
        account_name,
        {{ dim_group_by(dims=get_budget_dimensions(), trailing=true) }}
        scenario_id,
        cycle,
        layer,
        reporting_currency
),

{# The entity's residual per consolidation (gold_fx_revaluation's entity_residual, keyed on
   scenario, cycle and layer as well), with the ownership the core resolved for the period: one
   value per (group, entity, period), so any() reads it. #}
entity_residual as (
    select
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        scenario_id,
        cycle,
        layer,
        any(reporting_currency) as reporting_currency,
        any(ownership_pct) as ownership_pct,
        any(consolidation_method) as consolidation_method,
        -sum(group_amount) as cta_amount
    from {{ ref('gold_consolidated_budget_tb') }}
    group by
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        scenario_id,
        cycle,
        layer
),

{# Layer 3: CTA plug rows. #}
cta_entries as (
    select
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        'CTA' as main_account,
        'CTA' as account_name,
        {{ dim_empty_strings(dims=get_budget_dimensions(), trailing=true) }}
        scenario_id,
        cycle,
        layer,
        reporting_currency,
        cta_amount as amount,
        'cta' as adjustment_type,
        '' as journal_id
    from entity_residual
),

{# Layer 7: NCI attribution. The minority's share of the period's P&L, per consolidation. #}
result as (
    select
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        scenario_id,
        cycle,
        layer,
        sum(toFloat64(nci_amount)) as result_share
    from {{ ref('gold_consolidated_budget_tb') }}
    where is_pnl = 1
    group by
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        scenario_id,
        cycle,
        layer
),

{# Scope as gold_nci_attribution_journal's: full method, below 100%. has_complete_chain = 1 is
   already the core's filter. An unmatched LEFT JOIN fills 0 under join_use_nulls = 0: no P&L row
   reads as a zero result share, which is what is meant. #}
shares as (
    select
        er.consolidation_group as consolidation_group,
        er.data_area_id as data_area_id,
        er.fiscal_year as fiscal_year,
        er.fiscal_period as fiscal_period,
        er.scenario_id as scenario_id,
        er.cycle as cycle,
        er.layer as layer,
        er.reporting_currency as reporting_currency,
        r.result_share as result_share,
        (1.0 - er.ownership_pct) * toFloat64(er.cta_amount) as cta_share
    from entity_residual as er
    left join result as r
        on r.consolidation_group = er.consolidation_group
        and r.data_area_id = er.data_area_id
        and r.fiscal_year = er.fiscal_year
        and r.fiscal_period = er.fiscal_period
        and r.scenario_id = er.scenario_id
        and r.cycle = er.cycle
        and r.layer = er.layer
    where er.consolidation_method = 'full'
      and er.ownership_pct < 1 - 0.000001
      and (abs(r.result_share) > 0.000001
           or abs((1.0 - er.ownership_pct) * toFloat64(er.cta_amount)) > 0.000001)
),

group_nci as (
    {{ ic_group_nci_accounts() }}
),

re_account as (
    select
        min(main_account_id) as re_account,
        argMin(account_name, main_account_id) as re_name
    from {{ ref('silver_main_accounts') }}
    where is_retained_earnings = 1
),

nci_names as (
    select main_account_id, any(account_name) as account_name
    from {{ ref('silver_main_accounts') }}
    group by main_account_id
),

journal as (
    select
        sh.consolidation_group as consolidation_group,
        sh.data_area_id as data_area_id,
        sh.fiscal_year as fiscal_year,
        sh.fiscal_period as fiscal_period,
        sh.scenario_id as scenario_id,
        sh.cycle as cycle,
        sh.layer as layer,
        sh.reporting_currency as reporting_currency,
        sh.result_share as result_share,
        sh.cta_share as cta_share,
        gn.declared_nci_account as nci_account,
        if(nn.account_name = '', gn.declared_nci_account, nn.account_name) as nci_name,
        re.re_account as re_account,
        re.re_name as re_name,
        concat('NCI-', sh.consolidation_group, '-', sh.data_area_id, '-',
               toString(sh.fiscal_year), '-P', toString(sh.fiscal_period), '-',
               sh.scenario_id, '-', sh.cycle, '-', sh.layer) as journal_id
    from shares as sh
    inner join group_nci as gn
        on gn.nci_group = sh.consolidation_group
        and gn.declared_nci_account != ''
    cross join re_account as re
    left join nci_names as nn
        on nn.main_account_id = gn.declared_nci_account
    where re.re_account != ''
),

nci_attribution as (
    select
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        re_account as main_account,
        re_name as account_name,
        {{ dim_empty_strings(dims=get_budget_dimensions(), trailing=true) }}
        scenario_id,
        cycle,
        layer,
        reporting_currency,
        -result_share as amount,
        'nci_attribution' as adjustment_type,
        journal_id
    from journal
    where abs(result_share) > 0.000001

    union all

    select
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        'CTA' as main_account,
        'CTA' as account_name,
        {{ dim_empty_strings(dims=get_budget_dimensions(), trailing=true) }}
        scenario_id,
        cycle,
        layer,
        reporting_currency,
        -cta_share as amount,
        'nci_attribution' as adjustment_type,
        journal_id
    from journal
    where abs(cta_share) > 0.000001

    union all

    select
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        nci_account as main_account,
        nci_name as account_name,
        {{ dim_empty_strings(dims=get_budget_dimensions(), trailing=true) }}
        scenario_id,
        cycle,
        layer,
        reporting_currency,
        result_share + cta_share as amount,
        'nci_attribution' as adjustment_type,
        journal_id
    from journal
    where abs(result_share + cta_share) > 0.000001
),

{# Union of the three layers; 'ic_elimination', the deal journals, 'topside' and 'equity_method'
   are absent by decision (konsol#427, #425): see the header. #}
all_layers as (
    select * from entity_balances
    union all
    select * from cta_entries
    union all
    select * from nci_attribution
)

select * from all_layers
