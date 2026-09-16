{{ config(severity='warn') }}
-- konsolidat#218: an account that DECLARES historical translation, in a period no
-- Historical Equity Rate covers.
--
-- The decision (16 Sep 2026): the retained-earnings account declares its own
-- translation method; the product does not decide the policy. That makes this gap
-- load-bearing. A customer who declares `fx_method = 'historical'` on an account is
-- expected to supply Historical Equity Rates for it, and when a period is not
-- covered, gold_consolidated_trial_balance's `case` falls back to the closing rate
-- (`hr.historical_rate is not null` is false) — the right fallback, but until now a
-- silent one: nothing said WHICH account or WHICH period translated at the wrong
-- rate.
--
-- Division of labour with assert_equity_rate_coverage: that test answers "this
-- entity node has no equity rates AT ALL" (and names rates keyed to a non-node),
-- which is an entity-level master-data gap. It never mentions an account or a
-- period. This test answers the finer question the declaration creates: "this
-- account declares historical, and no rate covers THIS period". An entity can pass
-- that test — it has rates — and still be named here for the periods before its
-- first tranche.
--
-- Coverage is resolved EXACTLY the way translation resolves the rate, or the test
-- would disagree with the numbers (gold_consolidated_trial_balance, the `hr` ASOF
-- join):
--   * keys   (owner_group, data_area_id, main_account) — the entity's OWNING group,
--            not the consolidating one. A historical equity rate is recorded once,
--            under the node that owns the entity; after the multi-level fan-out the
--            same entity appears under every ancestor, all resolving to that one
--            owner group (F2). owner_group is not a column of the consolidated TB,
--            so it is read back from gold_entity_ownership on the same period key.
--   * as-of  the latest tranche whose rate_date <= period_date. A period BEFORE the
--            first tranche yields no rate — the case the ASOF join was fixed for
--            (konsolidat#92 finding 2: the old row_number()/rn=1 join took the most
--            recent tranche EVER and silently borrowed a future rate).
--   * period_date from build_date_from_year_period(), as the model builds it.
--
-- Severity warn, matching assert_equity_rate_coverage: a declared account with no
-- rate is master data with a defined fallback, not a broken ledger. It must name the
-- gap precisely enough to act on, which is what the message does.

{# The declaration itself, from the governed chart (konsolidat#213):
   uses_historical_rate is `fx_method = 'historical'`, which is what decides
   translation — not is_equity, which says what the account IS. #}
with declared as (
    select main_account_id
    from {{ ref('silver_main_accounts') }}
    where uses_historical_rate = 1
),

{# One row per (owning group, entity, declared account, period) that was actually
   consolidated. DISTINCT because the TB is grained finer than this (dimensions,
   partner) and because one entity fans out to every ancestor group — all of which
   share the one owner_group, so the fan-out must not multiply the findings. #}
candidates as (
    select distinct
        eo.owner_group as owner_group,
        ctb.data_area_id as data_area_id,
        ctb.main_account as main_account,
        ctb.fiscal_year as fiscal_year,
        ctb.fiscal_period as fiscal_period,
        {{ build_date_from_year_period('ctb.fiscal_year', 'ctb.fiscal_period') }} as period_date
    from {{ ref('gold_consolidated_trial_balance') }} as ctb
    inner join declared as d
        on ctb.main_account = d.main_account_id
    inner join {{ ref('gold_entity_ownership') }} as eo
        on eo.consolidation_group = ctb.consolidation_group
        and eo.data_area_id = ctb.data_area_id
        and eo.fiscal_year = ctb.fiscal_year
        and eo.fiscal_period = ctb.fiscal_period
),

rates as (
    select
        consolidation_group,
        data_area_id,
        main_account,
        rate_date
    from {{ source('epm_staging', 'historical_equity_rates') }}
),

{# The as-of count, on the model's keys. join_use_nulls=0: a LEFT-join miss fills
   rate_date with the Date default 1970-01-01, which is <= every period_date and
   would count as an eligible tranche — so presence is tested on the key
   (consolidation_group != ''), never inferred from the date. Same defaulting trap
   the model's own Nullable cast guards against. #}
resolved as (
    select
        c.owner_group as owner_group,
        c.data_area_id as data_area_id,
        c.main_account as main_account,
        c.fiscal_year as fiscal_year,
        c.fiscal_period as fiscal_period,
        c.period_date as period_date,
        countIf(r.consolidation_group != '' and r.rate_date <= c.period_date) as n_eligible_tranches
    from candidates as c
    left join rates as r
        on c.owner_group = r.consolidation_group
        and c.data_area_id = r.data_area_id
        and c.main_account = r.main_account
    group by
        c.owner_group,
        c.data_area_id,
        c.main_account,
        c.fiscal_year,
        c.fiscal_period,
        c.period_date
)

select
    owner_group,
    data_area_id,
    main_account,
    fiscal_year,
    fiscal_period,
    period_date,
    concat(
        'account ', main_account, ' declares fx_method = historical, but no Historical Equity Rate covers ',
        'FY', toString(fiscal_year), ' P', toString(fiscal_period),
        ' for entity ', data_area_id, ' under group ', owner_group,
        ': the balance translated at the CLOSING rate instead. Record a Historical Equity Rate for ',
        'this group, entity and account dated on or before ', toString(period_date), '.'
    ) as problem
from resolved
where n_eligible_tranches = 0
