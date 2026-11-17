{{ config(severity='warn') }}
-- konsol#348 S4 (#368 review, major): a BUDGET account that DECLARES historical translation, in a
-- period no Historical Equity Rate of its Cycle's Rate Set covers. The budget twin of
-- assert_declared_historical_has_a_rate (konsolidat#218), over gold_consolidated_budget_tb.
--
-- consolidation_core's `case` takes the as-of tranche when `hr.historical_rate is not null` and the
-- CLOSING rate otherwise, for the budget as for the actuals. The budget's HER join is keyed on the
-- row's rate_set (its Cycle's, konsol#348 S4 W4), so a tranche recorded in the actuals set is not
-- read for a budget: a site that keeps its historical rates under the actuals set only translates
-- every declared-historical budget balance at closing, with nothing said. budget_rate_gaps() (the
-- pre_hook guard) covers the governed Closing / Average rates only; this test names the historical
-- gap: scenario, Cycle, Rate Set, owning group, entity, account, presentation currency, period.
--
-- Coverage is resolved EXACTLY the way the core resolves the rate, or the test would disagree with
-- the numbers:
--   * keys   (owner_group, data_area_id, main_account, to_currency, rate_set): the entity's OWNING
--            group (the node that holds the entity: gold_budget_entity_ownership.owner_group, the
--            table the model consolidates on, since the model does not emit it), the consolidating
--            group's reporting_currency (konsol#374 option b), and the row's rate_set.
--   * as-of  the latest tranche whose rate_date <= period_date; a period before the first tranche
--            has none (konsolidat#92 finding 2).
--   * period_date the DECLARED window_end_date (gold_budget_entity_ownership.period_date, from
--            declared_periods()), the date the core joins on.
--   * rate rows the Cycles' sets only (budget_rate_set_predicate()), as the model reads them.
-- Same-currency rows are skipped (konsolidat#295): accounting_currency = reporting_currency
-- translates at 1.0 before the core looks at any rate. The declaration is the row's own
-- uses_historical_rate (the chart's fx_method = 'historical', carried to the output; konsolidat#213).
--
-- Severity warn, matching the actuals test: a declared account with no tranche is master data with
-- a defined fallback, named precisely enough to act on.
-- Fixtures: test_fixtures/assert_budget_declared_historical_has_a_rate.sql (tranche in the Cycle's
-- set: pass) and .must_flag.sql (tranche in the actuals set only: 2 rows).

{# One row per (scenario, cycle, set, owning group, entity, declared account, presentation
   currency, period) that was consolidated. owner_group and period_date come from
   gold_budget_entity_ownership, the ownership the model consolidates on (konsolidat#369).
   DISTINCT: the TB is grained finer (layer, dimensions), and ancestors presenting in one
   currency share the one owner_group. #}
with candidates as (
    select distinct
        b.scenario_id as scenario_id,
        b.cycle as cycle,
        b.rate_set as rate_set,
        eo.owner_group as owner_group,
        b.data_area_id as data_area_id,
        b.main_account as main_account,
        b.reporting_currency as reporting_currency,
        b.fiscal_year as fiscal_year,
        b.fiscal_period as fiscal_period,
        eo.period_date as period_date
    from {{ ref('gold_consolidated_budget_tb') }} as b
    inner join {{ ref('gold_budget_entity_ownership') }} as eo
        on eo.consolidation_group = b.consolidation_group
        and eo.data_area_id = b.data_area_id
        and eo.fiscal_year = b.fiscal_year
        and eo.fiscal_period = b.fiscal_period
    where b.uses_historical_rate = 1
      and b.accounting_currency != b.reporting_currency
),

{# The Cycles' sets' tranches only, as the model reads them. #}
rates as (
    select
        consolidation_group,
        data_area_id,
        main_account,
        to_currency,
        rate_set,
        rate_date
    from {{ source('epm_staging', 'historical_equity_rates') }}
    where {{ budget_rate_set_predicate() }}
),

{# join_use_nulls=0: a LEFT-join miss fills rate_date with 1970-01-01, which is <= every
   period_date; presence is tested on the key (consolidation_group != ''), never on the date. #}
resolved as (
    select
        c.scenario_id as scenario_id,
        c.cycle as cycle,
        c.rate_set as rate_set,
        c.owner_group as owner_group,
        c.data_area_id as data_area_id,
        c.main_account as main_account,
        c.reporting_currency as reporting_currency,
        c.fiscal_year as fiscal_year,
        c.fiscal_period as fiscal_period,
        c.period_date as period_date,
        countIf(r.consolidation_group != '' and r.rate_date <= c.period_date) as n_eligible_tranches
    from candidates as c
    left join rates as r
        on c.owner_group = r.consolidation_group
        and c.data_area_id = r.data_area_id
        and c.main_account = r.main_account
        and c.reporting_currency = r.to_currency
        and c.rate_set = r.rate_set
    group by
        c.scenario_id,
        c.cycle,
        c.rate_set,
        c.owner_group,
        c.data_area_id,
        c.main_account,
        c.reporting_currency,
        c.fiscal_year,
        c.fiscal_period,
        c.period_date
)

select
    scenario_id,
    cycle,
    rate_set,
    owner_group,
    data_area_id,
    main_account,
    reporting_currency,
    fiscal_year,
    fiscal_period,
    period_date,
    concat(
        'budget ', scenario_id, ' Cycle ', cycle, ': account ', main_account,
        ' declares fx_method = historical, but no Historical Equity Rate in Rate Set ', rate_set,
        ' into ', reporting_currency, ' covers FY', toString(fiscal_year), ' P', toString(fiscal_period),
        ' for entity ', data_area_id, ' under group ', owner_group,
        ': the budget balance translated at the CLOSING rate instead. Record a Historical Equity Rate for ',
        'this group, entity and account in Rate Set ', rate_set, ' with To Currency ', reporting_currency,
        ', dated on or before ', toString(period_date), '. A tranche in the actuals set is not read for a budget.'
    ) as problem
from resolved
where n_eligible_tranches = 0
