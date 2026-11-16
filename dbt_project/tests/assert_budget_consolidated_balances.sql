-- konsol#348 S4 (W6; S4-Q3 a, S4-Q8 b): the fully consolidated BUDGET balances by construction,
-- per consolidation of its own. gold_fully_consolidated_budget is gold_fully_consolidated_tb's
-- shape over gold_consolidated_budget_tb, with four layers; per (group, scenario, cycle, layer,
-- entity, period), L = sum of local amounts, G = sum of group_amount, C = the Closing rate in the
-- Cycle's Rate Set: 'entity' (G, by account), 'unbalanced' (-L x C, the budget's own local
-- imbalance), 'cta' (-(G - L x C), the translation difference only; the whole residual when
-- L = 0) and 'nci_attribution' (the gold_nci_attribution_journal formula: the minority's share
-- of the result and of the CTA, a journal that sums to zero). So within one consolidation the
-- adjustment types sum to 0: G - L x C - (G - L x C) is 0 by definition, and the attribution
-- journal nets to 0 on its own. A row here means a layer was computed on a different key than
-- the others: a plug summed across budget layers or Cycles (telescoping), the two plugs read
-- from different sums, an NCI journal whose lines were dropped by the zero-line filter on one
-- side only, or an entity layer that lost rows the plugs saw. The plugs' values are pinned by
-- assert_budget_consolidated_plugs_hand_table; this test proves only that they close.
--
-- Not covered, by design (konsol#427, #425): a budget has no partner, so there is no
-- 'ic_elimination' layer ("before eliminations"); deal journals and topside are actuals-only.
-- Nothing is missing from the sum because nothing else is posted.
--
-- Fixture: test_fixtures/assert_budget_consolidated_balances.sql (a EUR entity in a USD group,
-- 80% owned, two layers, two periods; hand values in its header). Vacuous when no Budget Cycle is
-- approved: the model is then empty.
-- Tolerance 0.01 in the group's currency: the amounts are Float64 sums of Decimal x Float64
-- products.
{{ config(severity='error') }}

select
    consolidation_group,
    scenario_id,
    cycle,
    layer,
    data_area_id,
    fiscal_year,
    fiscal_period,
    sum(amount) as net_amount,
    groupUniqArray(adjustment_type) as adjustment_types,
    count() as n_rows
from {{ ref('gold_fully_consolidated_budget') }}
group by
    consolidation_group,
    scenario_id,
    cycle,
    layer,
    data_area_id,
    fiscal_year,
    fiscal_period
having abs(sum(amount)) > 0.01
order by consolidation_group, scenario_id, cycle, layer, data_area_id, fiscal_year, fiscal_period
