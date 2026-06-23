-- grynn-in/konsolidat#92 finding #2: the historical equity rate applied to a
-- period must be the AS-OF rate (the latest tranche whose rate_date <=
-- period_date), not the most-recent-ever rate. The previous row_number()/rn=1
-- join ignored period_date, so an early period could get a future tranche's
-- rate. The existing assert_equity_uses_historical_rate test only checks that
-- *a* historical rate was used, not the correct-period one — this asserts the
-- period correlation.
--
-- Fails (returns rows) when, for a row that applied a historical rate:
--   * no tranche actually qualifies as-of the period (rate borrowed from the
--     future — the exact pre-fix bug), or
--   * the applied rate differs from the as-of expected rate.

with applied as (
    select
        consolidation_group,
        data_area_id,
        main_account,
        {{ build_date_from_year_period('fiscal_year', 'fiscal_period') }} as period_date,
        historical_equity_rate
    from {{ ref('gold_consolidated_trial_balance') }}
    where historical_equity_rate is not null
),

rates as (
    select
        consolidation_group,
        data_area_id,
        main_account,
        rate_date,
        toFloat64(historical_rate) as historical_rate
    from {{ source('epm_staging', 'historical_equity_rates') }}
),

expected as (
    select
        a.consolidation_group,
        a.data_area_id,
        a.main_account,
        a.period_date,
        a.historical_equity_rate,
        argMaxIf(r.historical_rate, r.rate_date, r.rate_date <= a.period_date) as expected_rate,
        countIf(r.rate_date <= a.period_date) as n_eligible_tranches
    from applied as a
    left join rates as r
        on a.consolidation_group = r.consolidation_group
        and a.data_area_id = r.data_area_id
        and a.main_account = r.main_account
    group by
        a.consolidation_group,
        a.data_area_id,
        a.main_account,
        a.period_date,
        a.historical_equity_rate
)

select *
from expected
where n_eligible_tranches = 0
   or abs(historical_equity_rate - expected_rate) > 0.000001
