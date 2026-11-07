-- konsolidat#279 / PRD-14: every equity-method associate with a non-zero result in a period, whose
-- accounting currency differs from its group's reporting currency, has exactly one usable governed
-- Average rate for that period into the group currency (epm_staging.group_exchange_rates,
-- konsolidat#93), keyed through rate_period_map() exactly as gold_equity_method_associates keys it
-- (a Closing-type period reads its year's last Regular period, konsolidat#199 row D9).
--
-- Why a sibling test and not the model's own stop. gold_equity_method_associates refuses to build
-- when an associate's Average rate is missing, duplicated or invalid (throwIf in its `translated`
-- CTE), but ClickHouse's throwIf takes a constant message, so the stop names no key, and the
-- line-consolidation guards do not cover an associate at all: governed_translated_keys() (the
-- pre_hook guard, assert_every_translated_currency_has_a_governed_rate, deploy.sh's fx_precheck)
-- excludes consolidation_method = 'equity' on purpose. Without this test an operator got "some
-- associate, some period". This lists every key, in the shape a person fixes it: approve the
-- Average rate in konsol Group Exchange Rate (or cancel the extra one).
--
-- reason is one of: missing (no approved Average rate for the rate key); duplicate (more than one
-- approved Average rate: the model's anyIf would pick one); invalid (an Average rate that is zero,
-- negative or not finite); no_reporting_currency (the group has no root row in
-- epm_gold.consolidation_groups, data_area_id = '', or its reporting_currency is blank, so there is
-- no currency to translate INTO: not a rate problem, fix the Consolidation Group in konsol. The
-- model stops on this first, with its own message, and the row is labelled so it is never read as
-- a missing rate).
--
-- Built from the model's own inputs (never from the model: a refused build must still let this
-- run and name the key). A zero result needs no rate (0 x anything is 0), and the model does not
-- stop on one either, so a zero-result period is not listed. join_use_nulls=0: a rate miss fills
-- n_average = 0 on the LEFT JOIN, so the count is the signal, never a NULL test across the join;
-- a group-root miss fills to_currency = ''.
--
-- severity warn, on purpose, as assert_every_translated_currency_has_a_governed_rate: this test
-- sits on the model's INPUTS, and at error severity a flag made `dbt build` SKIP
-- gold_equity_method_associates and everything below it before the model ran, so its throwIf never
-- decided and the fixture gate saw SKIPPED where it expected REFUSED (CI run 42393401046 on
-- 34eaddf). The model decides: its throwIf stops the build; this test, in the same run, names the
-- keys. A WARN here is never "fine": it is the list of what the refused build needs.
--
-- Fixtures: dbt_project/test_fixtures/assert_equity_associate_has_average_rate.must_flag.sql (SEK
-- associate in a EUR group with a Closing rate but no Average rate: 2 rows, FY2026 P12 and the
-- Closing period P13 that reads P12), ...no_reporting_currency.must_flag.sql (no root row: 2 rows),
-- and assert_equity_method_journal_balances.sql (the balanced case: passes).
{{ config(severity='warn') }}
with associate_results as (
    select
        eo.consolidation_group as consolidation_group,
        tb.data_area_id as data_area_id,
        ec.accounting_currency as from_currency,
        grp.reporting_currency as to_currency,
        toUInt16(tb.fiscal_year) as fiscal_year,
        toUInt16(tb.fiscal_period) as fiscal_period,
        if(rpm.mapped = 1, rpm.rate_year, toUInt16(tb.fiscal_year)) as rate_year,
        if(rpm.mapped = 1, rpm.rate_period, toUInt16(tb.fiscal_period)) as rate_period
    from {{ ref('gold_trial_balance') }} as tb
    inner join {{ ref('gold_entity_ownership') }} as eo
        on eo.data_area_id = tb.data_area_id
        and eo.fiscal_year = tb.fiscal_year
        and eo.fiscal_period = tb.fiscal_period
    inner join {{ ref('silver_main_accounts') }} as ma
        on ma.main_account_id = tb.main_account
    inner join (
        select data_area_id, accounting_currency
        from {{ ref('silver_entity_currencies') }}
        where accounting_currency != ''
    ) as ec
        on ec.data_area_id = tb.data_area_id
    left join {{ rate_period_map() }} as rpm
        on rpm.fiscal_year = tb.fiscal_year
        and rpm.fiscal_period = tb.fiscal_period
    left join (
        select consolidation_group, reporting_currency
        from {{ source('epm_gold', 'consolidation_groups') }}
        where data_area_id = ''
    ) as grp
        on grp.consolidation_group = eo.consolidation_group
    where eo.consolidation_method = 'equity'
      and eo.has_complete_chain = 1
      and ma.is_pnl = 1
    group by consolidation_group, data_area_id, from_currency, to_currency,
             fiscal_year, fiscal_period, rate_year, rate_period
    having sum(tb.period_net_amount) != 0
),

governed_average_rates as (
    select
        from_currency,
        to_currency,
        fiscal_year,
        fiscal_period,
        countIf(rate_type = 'Average') as n_average,
        countIf(rate_type = 'Average' and not (isFinite(rate) and rate > 0)) as n_invalid
    from {{ source('epm_staging', 'group_exchange_rates') }}
    group by from_currency, to_currency, fiscal_year, fiscal_period
)

select
    ar.consolidation_group as consolidation_group,
    ar.data_area_id as data_area_id,
    ar.from_currency as from_currency,
    ar.to_currency as to_currency,
    ar.fiscal_year as fiscal_year,
    ar.fiscal_period as fiscal_period,
    multiIf(
        ar.to_currency = '', 'no_reporting_currency',
        gr.n_average = 0, 'missing',
        gr.n_average > 1, 'duplicate',
        gr.n_invalid > 0, 'invalid',
        ''
    ) as reason
from associate_results as ar
left join governed_average_rates as gr
    on ar.from_currency = gr.from_currency
    and ar.to_currency = gr.to_currency
    and ar.rate_year = gr.fiscal_year
    and ar.rate_period = gr.fiscal_period
where ar.from_currency != ar.to_currency
  and reason != ''
order by consolidation_group, data_area_id, fiscal_year, fiscal_period
