-- grynn-in/konsolidat#92 finding #2: the historical equity rate applied to a
-- period must be the AS-OF rate (the latest tranche whose rate_date <=
-- period_date), not the most-recent-ever rate. The previous row_number()/rn=1
-- join ignored period_date, so an early period could get a future tranche's
-- rate. The existing assert_equity_uses_historical_rate test only checks that
-- *a* historical rate was used, not the correct-period one — this asserts the
-- period correlation.
--
-- konsol#374 (Deepak Pai, 7 Nov 2026, option b): a Historical Equity Rate
-- converts INTO one presentation currency (`to_currency`). A sub-group that
-- presents in EUR and its parent that presents in USD each need their own
-- rate for the same entity and account, and the model matches a rate on the
-- consolidating group's reporting_currency. The expected rate here is
-- therefore resolved exactly as the model resolves it: on the entity's OWNING
-- group (gold_entity_ownership.owner_group, where the rate is recorded once),
-- the entity, the account, AND the row's reporting currency. Keyed on the
-- consolidating group alone, a multi-level tree never matched a rate recorded
-- under the sub-group; keyed without the currency, two tranches for two
-- presentation currencies were one as-of series and the later one won at
-- both levels.
--
-- Fails (returns rows) when, for a row that applied a historical rate:
--   * no tranche into the row's reporting currency qualifies as-of the period
--     (rate borrowed from the future, or from another currency's series), or
--   * the applied rate differs from the as-of expected rate.

with applied as (
    select
        ctb.consolidation_group as consolidation_group,
        eo.owner_group as owner_group,
        ctb.data_area_id as data_area_id,
        ctb.main_account as main_account,
        ctb.reporting_currency as reporting_currency,
        {{ build_date_from_year_period('ctb.fiscal_year', 'ctb.fiscal_period') }} as period_date,
        ctb.historical_equity_rate as historical_equity_rate
    from {{ ref('gold_consolidated_trial_balance') }} as ctb
    inner join {{ ref('gold_entity_ownership') }} as eo
        on eo.consolidation_group = ctb.consolidation_group
        and eo.data_area_id = ctb.data_area_id
        and eo.fiscal_year = ctb.fiscal_year
        and eo.fiscal_period = ctb.fiscal_period
    where ctb.historical_equity_rate is not null
),

rates as (
    select
        consolidation_group,
        data_area_id,
        main_account,
        to_currency,
        rate_date,
        toFloat64(historical_rate) as historical_rate
    from {{ source('epm_staging', 'historical_equity_rates') }}
),

expected as (
    select
        a.consolidation_group as consolidation_group,
        a.owner_group as owner_group,
        a.data_area_id as data_area_id,
        a.main_account as main_account,
        a.reporting_currency as reporting_currency,
        a.period_date as period_date,
        a.historical_equity_rate as historical_equity_rate,
        argMaxIf(r.historical_rate, r.rate_date, r.rate_date <= a.period_date) as expected_rate,
        countIf(r.rate_date <= a.period_date) as n_eligible_tranches
    from applied as a
    left join rates as r
        on a.owner_group = r.consolidation_group
        and a.data_area_id = r.data_area_id
        and a.main_account = r.main_account
        and a.reporting_currency = r.to_currency
    group by
        a.consolidation_group,
        a.owner_group,
        a.data_area_id,
        a.main_account,
        a.reporting_currency,
        a.period_date,
        a.historical_equity_rate
)

select *
from expected
where n_eligible_tranches = 0
   or abs(historical_equity_rate - expected_rate) > 0.000001
