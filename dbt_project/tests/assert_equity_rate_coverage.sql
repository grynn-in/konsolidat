{{ config(severity='warn') }}
{#- konsolidat#176 review: warn, not error. Every row here is konsol master data
    (an entity with equity but no Historical Equity Rate), not ledger data, and the
    model has a defined fallback for it: equity translates at the closing rate.
    At error it made `dbt build` skip all 14 consolidation models, which the
    deploy now (rightly) treats as a failed build. It still names each gap. -#}
-- C2 / konsolidat#120, #232: IAS-21 equity-translation coverage guard.
--
-- Ask for a historical rate only where the model actually applies one.
--
-- konsolidat#232 (Deepak Pai, 21 September 2026 — option A). This used to require a
-- rate for every entity node in `consolidation_groups`: 329 of them on the live
-- stack, of which 44 have any trial balance and 40 hold equity. The tree is the
-- legal list — shells, dormant companies, intermediate holdings, branches that
-- never post; satellites inherit through ownership and do not file a TB. So the
-- check asked 285 entities for a rate covering equity they do not have, returned
-- 297 rows, and could never go green. Nobody read it.
--
-- The population is now derived from the CUSTOMER'S CHART rather than restated
-- here: an entity needs a rate when it holds a balance on an account the chart
-- marks `fx_method = 'historical'` (today 3000 Common stock, 3010 Additional
-- paid-in capital, 3020 Treasury stock) AND its functional currency differs from
-- the group's reporting currency. A site that marks a different account
-- historical gets the right check with no change here.
--
-- Rejected (konsolidat#232): adding 3100 Retained earnings. 3100 is
-- `fx_method = 'closing'` in this chart, so requiring a historical rate for it
-- would fail four entities for missing something the model never applies. If
-- opening retained earnings should translate at an opening rate, the honest
-- change is `3100.fx_method` — and this check then follows for free, which is
-- the point of reading the chart.
--
-- NOT COVERED, deliberately: scope by period. A disposed entity that still holds
-- historical equity accounts is asked for a rate. This test has no period
-- context, and ownership windows are a larger change — konsolidat#232 says so
-- rather than smuggling it in.
--
-- Two offender shapes, one row each:
--
--   missing_equity_rate_coverage — an entity holding equity the chart translates
--       at a historical rate, in a currency that must be translated, with no
--       `historical_equity_rates` row. Its equity silently falls back to the
--       closing rate. Also catches a rate keyed to a consolidation group the
--       join never matches (a #104-review bug).
--
--   orphan_equity_rate — a `historical_equity_rates` (group, entity) matching no
--       entity node: a dead rate no model can reference (the #120(b) guard).

with group_currency as (
    -- The rollup node carries the group's presentation currency; entity nodes
    -- carry a data_area_id, the rollup does not.
    select any(reporting_currency) as reporting_currency
    from {{ source('epm_gold', 'consolidation_groups') }}
    where data_area_id = ''
),

historical_accounts as (
    select distinct main_account_id
    from {{ ref('silver_main_accounts') }}
    where fx_method = 'historical'
),

-- Entities that actually hold one of those balances. A zero balance is not
-- equity to translate, so it does not demand a rate.
holds_historical_equity as (
    select distinct tb.data_area_id
    from {{ ref('gold_trial_balance') }} as tb
    inner join historical_accounts as ha
        on tb.main_account = ha.main_account_id
    where tb.period_net_amount != 0
),

-- ... and whose functional currency is not the group's. A USD-functional hub in
-- a USD group has no translation to get wrong.
must_translate as (
    -- aliased explicitly: ClickHouse carries the qualified name out of a
    -- CTE, so `h.data_area_id` is not addressable as `m.data_area_id` later.
    select h.data_area_id as data_area_id
    from holds_historical_equity as h
    inner join {{ ref('silver_entity_currencies') }} as ec
        on ec.data_area_id = h.data_area_id
    cross join group_currency as g
    where ec.accounting_currency != g.reporting_currency
),

scoped as (
    select distinct consolidation_group, data_area_id
    from {{ source('epm_gold', 'consolidation_groups') }}
    where data_area_id != ''
),

rates as (
    select distinct consolidation_group, data_area_id
    from {{ source('epm_staging', 'historical_equity_rates') }}
)

select
    s.consolidation_group,
    s.data_area_id,
    'missing_equity_rate_coverage' as reason
from scoped as s
inner join must_translate as m
    on m.data_area_id = s.data_area_id
where (s.consolidation_group, s.data_area_id) not in (
    select consolidation_group, data_area_id from rates
)

union all

select
    consolidation_group,
    data_area_id,
    'orphan_equity_rate' as reason
from rates
where (consolidation_group, data_area_id) not in (
    select consolidation_group, data_area_id from scoped
)
