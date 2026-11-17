{{
    config(
        materialized='table',
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# konsol#348 S4 (W6; S4-Q3 a, S4-Q4 a, S4-Q8 b): the fully consolidated BUDGET, in the shape of
   gold_fully_consolidated_tb plus three grain columns (scenario_id, cycle, layer), over
   gold_consolidated_budget_tb. S5's readers read the same columns for a budget as for the
   actuals: (consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account,
   account_name, the budget dimensions, scenario_id, cycle, layer, reporting_currency, amount,
   adjustment_type, journal_id). The grain columns sit after the dimensions, where the core
   placed them in gold_consolidated_budget_tb. The dimensions are the budget dimensions
   (get_budget_dimensions(), the chart's in_budget subset, BUD-8-2), as in that model.

   Four layers, each a consolidation of its own per (scenario, cycle, layer): a layer's plug is
   never computed across another layer, Cycle or scenario (that would telescope two
   consolidations into one; assert_budget_consolidated_balances catches it). For each (group,
   scenario, cycle, layer, entity, period) let
       L = sum of local_amount (the budget in the entity's currency),
       G = sum of group_amount (translated, at the operator's share for a joint operation),
       C = the period's Closing rate, entity currency -> group currency, in the Cycle's Rate Set
           (the row's closing_rate: the core resolved it from the governed rates keyed by
           rate_set and the mapped rate period; 1.0 for a same-currency entity),
       s = the share group_amount carries: ownership_pct for 'proportional', 1 otherwise.

   - 'entity'           sum(group_amount) per account and dimensions, as gold_fully_consolidated_tb's
                        layer 1. A budget has one row per key already (partner_data_area_id is ''
                        on every row), so the sum is over nothing but the key itself.
   - 'unbalanced'       -L x C x s (S4-Q8 b): the budget's OWN local imbalance, translated at the
                        closing rate. The actuals are double-entry (L = 0, a trial balance), but a
                        budget need not be: every Budget Annual Input is one line, so a P&L-only
                        budget (revenue and costs, nothing on the balance sheet) does not sum to
                        zero in its own currency. That gap is not a currency effect and is
                        reported as its own layer, on the literal main_account 'UNBALANCED',
                        dimensions blank, one row per consolidation (0 for a double-entry budget).
   - 'cta'              -(G - L x C x s): the TRANSLATION DIFFERENCE only, what the residual of a
                        double-entry budget would be. For L = 0 this is gold_fx_revaluation's whole
                        residual -sum(group_amount), unchanged; for L != 0 the local gap, which the
                        whole residual would have called CTA, is in 'unbalanced' instead. One plug
                        row per (group, entity, period) and here per (scenario, cycle, layer),
                        main_account the literal 'CTA', dimensions blank. A same-currency entity's
                        difference is 0 and the row is still emitted, as for the actuals.
   - 'nci_attribution'  gold_nci_attribution_journal's formula: for a full-method subsidiary owned
                        below 100%, result_share = sum(nci_amount) over the period's P&L rows and
                        cta_share = (1 - ownership) x the entity's CTA plug (the translation
                        difference above); lines retained-earnings -result_share, 'CTA' -cta_share,
                        the group's nci_account result_share + cta_share; a zero line is omitted, a
                        journal whose two shares are both 0 is omitted; no retained-earnings account
                        in the chart or no nci_account on the group's root means no journal (inner
                        joins, as there). What differs from the actuals' journal: ownership_pct and
                        consolidation_method are read from the budget rows themselves (the core
                        carries them from the budget's own ownership resolution, and already keeps
                        only has_complete_chain = 1 rows), not from gold_entity_ownership, whose
                        spine is the actuals' periods; and the year-end close exclusion is moot
                        (a budget posts no close rows, is_year_end_close is 0 throughout). The
                        minority takes no share of 'unbalanced': it is neither a result nor OCI.
                        journal_id is 'NCI-{group}-{entity}-{FY}-P{period}-{scenario}-{cycle}-{layer}'.

   G + (-L x C x s) + (-(G - L x C x s)) = 0, and the attribution journal nets to 0 on its own, so
   within one (group, scenario, cycle, layer, entity, period) the layers sum to 0 by construction
   (assert_budget_consolidated_balances, error); assert_budget_consolidated_plugs_hand_table pins
   the two plugs as literals on a double-entry and on a P&L-only fixture.

   C is never 0 or 1 by default. The core's throwIf refuses a row whose Cycle's set has no usable
   Closing and Average rate (translation_rate null), and budget_rate_guard refuses the build by
   name before that; if a row still reached here with a closing_rate that is not a positive
   finite number, `refusal` stops this build naming the consolidation.

   Absent, by decision:
   - 'ic_elimination' (konsol#427): a budget has no partner, so no intercompany pair exists to
     eliminate. This model is the budget BEFORE ELIMINATIONS, and every reader labels it so.
   - deal journals ('acquisition', 'goodwill_amortisation', 'disposal', 'pnl_proration'),
     'topside' and 'equity_method' (konsol#425): actuals-only journals with no scenario key.

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

{# The entity's sums per consolidation (gold_fx_revaluation's entity_residual, keyed on scenario,
   cycle and layer as well), with the ownership and the closing rate the core resolved for the
   period: one value each per (group, entity, period, set), so any() reads them. Aliases differ
   from the column names a sibling aggregate reads (CYCLIC_ALIASES). #}
entity_sums as (
    select
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        scenario_id,
        cycle,
        layer,
        any(reporting_currency) as group_currency,
        any(accounting_currency) as entity_currency,
        any(ownership_pct) as pct,
        any(consolidation_method) as method,
        any(closing_rate) as c_rate,
        toFloat64(sum(local_amount)) as local_sum,
        toFloat64(sum(group_amount)) as group_sum
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

{# S4-Q8 (b): L x C x s, then the two plugs. #}
entity_residual as (
    select
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        scenario_id,
        cycle,
        layer,
        group_currency as reporting_currency,
        entity_currency,
        pct as ownership_pct,
        method as consolidation_method,
        c_rate as closing_rate,
        -(local_sum * c_rate * if(method = 'proportional', pct, 1.0)) as unbalanced_amount,
        -(group_sum - local_sum * c_rate * if(method = 'proportional', pct, 1.0)) as cta_amount
    from entity_sums
),

{# A consolidation whose closing rate is not a positive finite number. The core and the pre_hook
   guard refuse such a build earlier; this names the key if one gets through, and never plugs at
   0 or 1. The outer WHERE keeps the row only when there is something to refuse, so the CAST (which
   raises with its message) is never evaluated on a clean run. #}
refusal as (
    select cast(
        concat(
            'konsol#348 S4-Q8 refused before the fully consolidated budget was replaced: ', toString(n),
            ' consolidation(s) with no usable Closing rate for the unbalanced / CTA split (closing_rate must be a positive finite number in the Cycle''s Rate Set): ',
            keys, '. No fallback: no plug is translated at 0 or 1.0.'
        ) as UInt8) as refused
    from (
        select
            count() as n,
            arrayStringConcat(arraySlice(arraySort(groupArray(
                concat(consolidation_group, ' ', data_area_id, ' ', scenario_id, ' ', cycle, ' ', layer,
                       ' FY', toString(fiscal_year), ' P', toString(fiscal_period), ' ',
                       entity_currency, '->', reporting_currency, ' closing_rate ', toString(closing_rate)))), 1, 50), '; ') as keys
        from entity_residual
        where not (closing_rate > 0 and isFinite(closing_rate))
    )
    where n > 0
),

{# Layer 2 (budget only): the budget's own local imbalance at the closing rate. #}
unbalanced_entries as (
    select
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        'UNBALANCED' as main_account,
        'Unbalanced budget' as account_name,
        {{ dim_empty_strings(dims=get_budget_dimensions(), trailing=true) }}
        scenario_id,
        cycle,
        layer,
        reporting_currency,
        unbalanced_amount as amount,
        'unbalanced' as adjustment_type,
        '' as journal_id
    from entity_residual
),

{# Layer 3: CTA plug rows, the translation difference only. #}
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
        (1.0 - er.ownership_pct) * er.cta_amount as cta_share
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
           or abs((1.0 - er.ownership_pct) * er.cta_amount) > 0.000001)
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

{# Union of the four layers; 'ic_elimination', the deal journals, 'topside' and 'equity_method'
   are absent by decision (konsol#427, #425): see the header. #}
all_layers as (
    select * from entity_balances
    union all
    select * from unbalanced_entries
    union all
    select * from cta_entries
    union all
    select * from nci_attribution
)

{# max() over the empty `refusal` is 0; a non-empty `refusal` raises with its message. #}
select * from all_layers
where (select max(refused) from refusal) = 0
