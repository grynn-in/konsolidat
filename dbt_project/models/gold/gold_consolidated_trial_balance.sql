{{
    config(
        materialized='incremental',
        incremental_strategy='append',
        pre_hook=[
            "{{ governed_rate_guard() }}",
            "{% if is_incremental() %}ALTER TABLE {{ this }} ADD COLUMN IF NOT EXISTS partner_data_area_id String DEFAULT ''{% endif %}",
            "{% if is_incremental() %}ALTER TABLE {{ this }} ADD COLUMN IF NOT EXISTS uses_historical_rate UInt8 DEFAULT 0{% endif %}",
            "{% if is_incremental() %}ALTER TABLE {{ this }} ADD COLUMN IF NOT EXISTS retranslation_amount Float64 DEFAULT 0{% endif %}",
            "{% if is_incremental() %}DELETE FROM {{ this }} WHERE 1 = 1 {{ period_filter() }} {{ scope_filter() }}{% endif %}"
        ],
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# konsolidat#93: the first pre_hook (macros/governed_rates.sql) raises when a
   currency this run translates has no approved governed rate, BEFORE the
   DELETE below, so a missing rate leaves the table as it was. The throwIf in
   `consolidated` stays as the second line of defence. #}
{# konsol#159: partner_data_area_id rides through from gold_trial_balance, so
   gold_ic_reconciliation can pair (entity, partner) with (partner, entity) on
   translated group amounts.

   A pre_hook (after the rate guard, before the DELETE) adds it to a table built
   before it existed. dbt-clickhouse's append inserts POSITIONALLY into the
   target's columns and applies no on_schema_change on this path, so the new
   column must sit where ALTER ... ADD COLUMN puts it: at the end. Anywhere
   else every later column would land one place off, silently. #}
{# konsolidat#213: uses_historical_rate follows the same rule, and its ALTER runs
   after partner_data_area_id's — so the table's last two columns are
   partner_data_area_id, then uses_historical_rate, and the final select below
   emits them in exactly that order. Any further column goes after both. #}
{# konsolidat#257: retranslation_amount is that further column. Its ALTER runs
   third, so the table ends partner_data_area_id, uses_historical_rate,
   retranslation_amount, and the final select emits them in that order. #}

{# #154: delete the run's WHOLE scope, then append. delete+insert deleted only
   the keys the new batch produced, so a key that left the SELECT (an ownership
   window ending, a currency that stopped resolving, a method change) kept its
   last rows forever. No vars => no predicate => the whole table is replaced.
   An entity removed from the group tree is outside scope_filter, so only the
   next unscoped build clears it. #}

{# A2 / grynn-in/konsolidat#116: incremental-by-period materialization.
   This is the consolidation CHOKEPOINT, so a scoped orchestrator close
   (entity_scope / fiscal_year[ / fiscal_period] vars) narrows the SELECT to its
   slice. With delete+insert keyed on the close slice
   (consolidation_group, data_area_id, fiscal_year, fiscal_period) a scoped run
   replaces ONLY its slice and leaves every other slice intact, instead of
   OVERWRITING the whole table. The pre_hook above deletes the slice with the
   same filters the SELECT uses; the SELECT then appends it. `dbt --full-refresh`
   (or the first build) drops + recreates the table from scratch. #}

{# PRD-1: Proper FX translation — closing rate for BS, average rate for PnL,
          from the governed group rates only (konsolidat#93 / konsol#103).
   FX CONTRACT (13 Sep 2026): epm_staging.group_exchange_rates.rate is the true
   rate (units of to_currency per 1 from_currency), published by konsol, the
   single source of FX rates. The warehouse never scales or inverts it.
   silver_exchange_rates holds the ERP quotes, which feed only konsol's
   pre-fill.
   PRD-4: Minority interest — nci_amount column for partial ownership
   PRD-8: Multi-level hierarchy — effective_ownership from hierarchy or seed fallback
   PRD-9: Temporal ownership — period-level ownership from ownership_periods staging
   PRD-10: Historical equity rates — equity accounts use historical rate (IAS 21) #}

with entity_tb as (
    select
        tb.data_area_id as data_area_id,
        tb.fiscal_year as fiscal_year,
        tb.fiscal_period as fiscal_period,
        tb.main_account as main_account,
        tb.account_name as account_name,
        tb.account_type_name as account_type_name,
        tb.is_balance_sheet as is_balance_sheet,
        tb.is_pnl as is_pnl,
        {# konsolidat#213: two facts, two columns, both taken from silver — this
           model no longer derives either.
             is_equity            what the account IS: the chart types it as
                                  Equity (account_type = 'Equity'), the meaning
                                  konsol's deal layer uses. It decides nothing
                                  about translation.
             uses_historical_rate what the chart DECLARES about translation
                                  (fx_method = 'historical'), which is what the
                                  rate below reads.
           konsol#182 derived is_equity from fx_method right here, so an asset
           declared at the historical rate answered "is this equity?" with yes.
           join_use_nulls=0: a LEFT-join miss reads 0 for both, so an undeclared
           account is neither equity nor declared at the historical rate. #}
        ma.is_equity as is_equity,
        ma.fx_method as fx_method,
        ma.uses_historical_rate as uses_historical_rate,
        {# konsolidat#259: the two facts the year-end close translation keys on,
           both declared upstream: the chart's retained-earnings flag and the
           close mark silver_tb_movements puts on the rows it synthesizes. Read
           by `closed` below and never selected into this model. #}
        toUInt8(ma.is_retained_earnings) as is_retained_earnings,
        toUInt8(tb.is_year_end_close) as is_year_end_close,
        tb.partner_data_area_id as partner_data_area_id,
        {{ dim_select(prefix='tb.', trailing=true) }}
        {# Signed double-entry movement (debit − credit), so the local TB sums
           to zero and the FX/CTA plug can balance it. Amounts arrive signed at
           the ERP boundary (models/staging/README.md). Silver splits them once
           into debit_amount / credit_amount by sign, and nothing after that
           infers a sign again. period_net_amount holds the same number
           (sum(debit) - sum(credit), per assert_period_net_equals_debit_minus_credit).
           It is no longer the positive magnitude #64 described. #}
        tb.period_debit - tb.period_credit as local_amount,
        ec.accounting_currency as accounting_currency,
        {# konsolidat#199 (row D9): the period whose governed rates this row
           translates at. Itself, except a Closing-type period, which has no
           rates of its own and uses the same fiscal year's last Regular
           period's (macros/governed_rates.sql, rate_period_map(): the guard
           requires the rate at the same key). A period konsol's calendar does
           not know maps to itself: a LEFT JOIN miss reads mapped = 0 under
           join_use_nulls=0 (an Opening period is legitimately numbered 0, so
           the flag, not the number, decides). Read by `rated`'s
           governed_rates join and never selected into it: this model appends
           by position, so no column may be added before partner_data_area_id. #}
        if(rpm.mapped = 1, rpm.rate_year, toUInt16(tb.fiscal_year)) as rate_year,
        if(rpm.mapped = 1, rpm.rate_period, toUInt16(tb.fiscal_period)) as rate_period,
        {{ build_date_from_year_period('tb.fiscal_year', 'tb.fiscal_period') }} as period_date
    {# konsol#159: the partner-grained twin of gold_trial_balance. That model
       stays at the account grain for its own readers; see
       gold_trial_balance_by_partner. #}
    from {{ ref('gold_trial_balance_by_partner') }} as tb
    {# konsol#110: the currency comes from silver_entity_currencies — konsol's
       Entity master first, the ERP's company master second. This used to join
       silver_legal_entities, which knows only entities an ERP extracted, so a
       connector-less entity's submitted trial balance reached gold_trial_balance
       and then vanished here with nothing failing.

       Resolved currencies only. An entity with no currency on either side
       would otherwise join with '', miss every rate key, and translate at the
       1.0 parity fallback — a JPY ledger landing as CHF, ~170x. Dropping it is
       the lesser wrong, and not a silent one: assert_every_tb_entity_has_a_currency
       names it. Filtered in the subquery so the rule sits with the source of
       the currencies. (An AND of a non-equality in ON also works on 24.8; only
       `x IN (col, ...)` is refused there.) #}
    inner join (
        select data_area_id, accounting_currency
        from {{ ref('silver_entity_currencies') }}
        where accounting_currency != ''
    ) as ec
        on tb.data_area_id = ec.data_area_id
    {# konsol#182: each account's declared fx_method, from the konsol group chart.
       LEFT on purpose: an undeclared account stays in the consolidation, and
       under join_use_nulls=0 its fx_method is '' — translated at the closing
       rate, as an unclassified account always was
       (assert_undeclared_accounts_in_trial_balance names it). silver holds one
       row per account (limit 1 by), so this cannot fan out. fx_method is read
       by `rated` and never selected into it: this model appends by position,
       so no column may be added before partner_data_area_id. #}
    left join (
        select main_account_id, fx_method, is_equity, uses_historical_rate, is_retained_earnings
        from {{ ref('silver_main_accounts') }}
    ) as ma
        on tb.main_account = ma.main_account_id
    {# konsolidat#199 (row D9): the Closing-period rule, one row per calendar
       period; see rate_year / rate_period above. #}
    left join {{ rate_period_map() }} as rpm
        on rpm.fiscal_year = tb.fiscal_year
        and rpm.fiscal_period = tb.fiscal_period
    {# Orchestrator run filters (opt-in; no var => no predicate => full build).
       period_filter = single-period close; scope_filter = one entity/group.
       Applied at the consolidation chokepoint so every downstream
       consolidation model (fully-consolidated TB, cash flow, YTD, NCI) inherits
       the slice, while foundational gold_trial_balance stays complete.
       konsolidat#257: only scope_filter is applied here. period_filter moved to
       the final select: the retranslation windows below need the entity's
       history, so a scoped close of one period still sees every earlier one.
       scope_filter can stay, because the windows partition by entity. #}
    where 1 = 1
        {{ scope_filter('tb.data_area_id') }}
),

{# F2: ownership is resolved in ONE place, gold_entity_ownership, and it is
   resolved per ANCESTOR group — which is what makes this model multi-level.
   Before F2 this CTE read the consolidation_groups seed and joined an entity to
   its immediate parent group only, so GROUP_CORP's consolidated result held
   JPMF and USMF and none of GROUP_EMEA's entities at any percentage. Now one
   entity yields one row per ancestor group, each at the chain-product share.

   The three-way `if(x != 0, ...)` fallback between staging, hierarchy and seed
   is gone with it: it read a deliberate 0% as "unset" and silently substituted
   a different source's number. #}
entity_ownership as (
    select
        eo.consolidation_group as consolidation_group,
        eo.data_area_id as data_area_id,
        eo.fiscal_year as fiscal_year,
        eo.fiscal_period as fiscal_period,
        eo.effective_ownership_pct as ownership_pct,
        eo.consolidation_method as consolidation_method,
        eo.has_complete_chain as has_complete_chain,
        eo.owner_group as owner_group,
        {# The GROUP's presentation currency, taken from the group node — not
           from the entity's own row, whose reporting_currency in the old seed
           was the group's anyway (it is NOT the entity's functional currency;
           that is silver_entity_currencies.accounting_currency). #}
        grp.reporting_currency as reporting_currency
    from {{ ref('gold_entity_ownership') }} as eo
    left join {{ source('epm_gold', 'consolidation_groups') }} as grp
        on grp.consolidation_group = eo.consolidation_group
        and grp.data_area_id = ''
),

{# PRD-10: Historical equity rates from staging #}
historical_rates as (
    select
        consolidation_group,
        data_area_id,
        main_account,
        rate_date,
        toFloat64(historical_rate) as historical_rate
    from {{ source('epm_staging', 'historical_equity_rates') }}
),

{# konsolidat#93 / konsol#103: translation reads ONLY the group's governed
   rates. Group finance approves one Closing and one Average rate per fiscal
   period, from each currency into a group reporting currency, in konsol's
   Group Exchange Rate; the submitted rows arrive here. The ERP feed
   (silver_exchange_rates) no longer reaches this model. It only pre-fills
   drafts in konsol, so neither a second ERP instance's drifting rate table nor
   an ERP's rate-type names ('Closing' / 'Average' / 'Default' as typed into
   the demo D365) can change a consolidated figure. The two strings below are
   the governed table's own rate types (konsol's Select), not an ERP's names.

   Keyed on the period itself, not an as-of date: a period's rate is the one
   approved for it. No fallback of any kind. The one declared exception is not
   a fallback: a Closing-type period (the year-end close of a period-end-balance
   file, konsolidat#199) has no rates of its own and is keyed on its year's
   last Regular period (rate_year / rate_period in entity_tb, from
   rate_period_map()); the guard requires the rate at that same key. A
   translated currency with no approved rate stops the build (see
   `consolidated`), and assert_every_translated_currency_has_a_governed_rate
   names it. The old chain (Closing, else Default, else 1.0) translated whole
   ledgers at the 1.0 parity rate without a word (#109). #}
{# The pre_hook guard also reads the currencies' reference magnitudes and the
   fiscal calendar; declared here so dbt knows the dependencies at parse time. #}
-- depends_on: {{ source('epm_gold', 'currencies') }} {{ source('epm_staging', 'fiscal_periods') }}
governed_rates as (
    select
        from_currency,
        to_currency,
        fiscal_year,
        fiscal_period,
        {# One approved row per key: konsol refuses a second approval, and a
           collision stops the run in the pre_hook guard (and is NULLed below);
           assert_governed_rate_grain_unique names it (warn). anyIf over no rows
           is 0, so presence is counted, never inferred from the value.
           `rate` is used exactly as published: the true rate. #}
        anyIf(toFloat64(rate), rate_type = 'Closing') as gov_closing,
        anyIf(toFloat64(rate), rate_type = 'Average') as gov_average,
        countIf(rate_type = 'Closing') as n_closing,
        countIf(rate_type = 'Average') as n_average,
        countIf(not (isFinite(rate) and rate > 0)) as n_invalid
    from {{ source('epm_staging', 'group_exchange_rates') }}
    group by from_currency, to_currency, fiscal_year, fiscal_period
),

{# Resolve per-row rate, ownership and translation_rate once.
   PRD-1 + PRD-10: translation rate depends on account type — equity → historical
   (fallback closing), BS → closing, PnL → average. A same-currency entity
   (accounting = reporting) ALWAYS translates at 1.0 regardless of what the rate
   table happens to contain (it carries scrambled same-currency rows, e.g.
   USD→USD ≠ 1 / CHF→CHF absent), so the local TB passes through unchanged and
   produces zero CTA. #}
rated as (
    select
        eo.consolidation_group as consolidation_group,
        etb.data_area_id as data_area_id,
        etb.fiscal_year as fiscal_year,
        etb.fiscal_period as fiscal_period,
        etb.main_account as main_account,
        etb.account_name as account_name,
        etb.account_type_name as account_type_name,
        etb.is_balance_sheet as is_balance_sheet,
        etb.is_pnl as is_pnl,
        {# konsolidat#213: silver's flag, in the position it has always had so
           every reader keeps the column it selects — but it now means
           account_type = 'Equity'. The translation declaration is
           uses_historical_rate, carried at the end of this select. #}
        etb.is_equity as is_equity,
        etb.partner_data_area_id as partner_data_area_id,
        {{ dim_select(prefix='etb.', trailing=true) }}
        etb.local_amount as local_amount,
        etb.accounting_currency as accounting_currency,
        eo.reporting_currency as reporting_currency,
        {# Already a fraction and already period-resolved — see
           gold_entity_ownership. No fallback chain, and 0% means 0%. #}
        eo.ownership_pct as ownership_pct,
        eo.consolidation_method as consolidation_method,
        {# A same-currency entity's rates are 1 by definition, not a lookup. #}
        if(etb.accounting_currency = eo.reporting_currency, 1.0, gr.gov_closing) as closing_rate,
        if(etb.accounting_currency = eo.reporting_currency, 1.0, gr.gov_average) as average_rate,
        {# PRD-10: Historical equity rate lookup #}
        hr.historical_rate as historical_equity_rate,
        case
            when etb.accounting_currency = eo.reporting_currency then 1.0
            {# Not exactly one approved Closing and one Average rate, or a rate
               that is zero, negative or not finite: NULL here, and
               `consolidated` stops the build on it (the pre_hook guard has
               normally stopped it already). Checked before the historical
               equity rate, so an equity tranche cannot hide a period the group
               never approved usable rates for. #}
            when gr.n_closing != 1 or gr.n_average != 1 or gr.n_invalid > 0 then null
            {# konsol#182: the account's declared fx_method decides, not its
               statement. historical takes the as-of tranche and, before the
               first tranche, the closing rate (as before); average is the
               period average; closing, and an undeclared account, the
               closing rate. A P&L account may be declared at closing (IAS 29
               hyperinflation). #}
            when etb.fx_method = 'historical' and hr.historical_rate is not null then hr.historical_rate
            when etb.fx_method = 'average' then gr.gov_average
            else gr.gov_closing
        end as translation_rate,
        {# konsolidat#213: the declaration, carried to the output so a reader can
           ask what the chart declared without re-deriving it from fx_method.
           LAST here and last in the model, for the positional-append reason at
           the top of this file. #}
        etb.uses_historical_rate as uses_historical_rate,
        {# konsolidat#257: the declaration the retranslation keys on. Never
           selected into the model (the final select excludes it). #}
        etb.fx_method as fx_method,
        {# konsolidat#259: never selected into the model either. #}
        etb.is_retained_earnings as is_retained_earnings,
        etb.is_year_end_close as is_year_end_close
    from entity_tb as etb
    {# One row per ancestor group: the fan-out here IS the multi-level
       consolidation. Period-keyed, because ownership is dated. #}
    inner join entity_ownership as eo
        on etb.data_area_id = eo.data_area_id
        and etb.fiscal_year = eo.fiscal_year
        and etb.fiscal_period = eo.fiscal_period
    {# join_use_nulls=0: a miss fills 0s, so n_closing / n_average = 0 is the
       "no approved rate" signal (never a NULL test across the join).
       Keyed on the mapped rate period (konsolidat#199, row D9): the row's own
       period, or its year's last Regular period for a Closing period. #}
    left join governed_rates as gr
        on etb.accounting_currency = gr.from_currency
        and eo.reporting_currency = gr.to_currency
        and etb.rate_year = gr.fiscal_year
        and etb.rate_period = gr.fiscal_period
    {# PRD-10: Historical equity rate — as-of the period: pick the latest tranche
       whose rate_date <= period_date. The previous row_number()/rn=1 took the
       single most-recent rate_date EVER, ignoring the period entirely, so an
       early period got a future rate (grynn-in/konsolidat#92, finding #2). An
       ASOF join (same pattern as ownership_staging above) selects the closest
       rate_date not exceeding period_date — and yields no match (NULL rate, so
       the case falls back to closing_rate) for periods before the first tranche,
       instead of silently borrowing a future rate. #}
    asof left join (
        select
            consolidation_group,
            data_area_id,
            main_account,
            rate_date,
            {# Nullable so an ASOF miss (period before the first tranche) yields
               NULL, not 0.0 — a non-nullable column would default to 0 on a
               LEFT-join miss and make the `hr.historical_rate is not null`
               fallback below wrongly translate equity at rate 0 (zeroing the
               balance) instead of closing_rate. Same defaulting trap the
               ownership block above guards against. #}
            cast(toFloat64(historical_rate) as Nullable(Float64)) as historical_rate
        from {{ source('epm_staging', 'historical_equity_rates') }}
    ) as hr
        {# F2: on the entity's OWNING group, not the consolidating one. A
           historical equity rate is recorded once, under the node that owns the
           entity; keying on eo.consolidation_group after the multi-level
           fan-out missed at every ancestor above it, so the same equity account
           translated at the acquisition rate in the sub-group and silently fell
           through to the closing rate in the parent — two different CTAs for
           one entity. #}
        on eo.owner_group = hr.consolidation_group
        and etb.data_area_id = hr.data_area_id
        and etb.main_account = hr.main_account
        and etb.period_date >= hr.rate_date
    {# PRD-14: equity-method entities are handled in a separate model. The
       method is the WEAKEST link on the chain, so an entity below an
       equity-held sub-group is excluded from that group's line consolidation
       too — while still line-consolidating into the sub-group itself.

       'none' is excluded as well: it is a real option on Ownership Period, and
       it is also gold_entity_ownership's catch-all rank for an unrecognised
       method — so a typo must not line-consolidate an entity at its full share
       with no NCI schedule row behind it (that model filters on 'full').

       A chain with an unresolved link consolidates nothing rather than
       something plausible; assert_ownership_chain_complete names it. #}
    where eo.consolidation_method not in ('equity', 'none')
      and eo.has_complete_chain = 1
),

{# konsolidat#257: a balance sheet balance is translated at the CLOSING rate of
   each reporting date (IAS 21.39(a)), not as the sum of each period's movement
   at its own period's closing rate.

   The model keeps the movement grain, so no reader changes its contract. The
   translated movement of a retranslated key telescopes instead:

       translated(p)        = cum_local(p) x C(p) - cum_local(prev) x C(prev)
                            = local(p) x C(p) + retranslation_amount(p)
       retranslation_amount = cum_local(prev) x (C(p) - C(prev))

   so the translated movements summed to p are cum_local(p) x C(p).

   Which keys (declared chart facts only, never an account code): a balance
   sheet account that is not equity and is declared 'closing' or undeclared.
   Equity is never revalued (decided on #257 Q2, 6 Oct 2026): it keeps movement
   x declared rate whatever its fx_method, so `closing` on an equity account
   means the closing rate of the period the amount was posted. Retranslating it
   would bury the exchange difference in equity lines and leave no separate
   component to recycle on disposal (IAS 21.39(c), .48).

   The key is (group, entity, account, partner, dimensions). prev is the key's
   previous row in this group, over the rows that survived the ownership join,
   so an acquired entity's group balance is its in-scope movements at today's
   closing rate.

   Densify: a key whose balance did not move in a period of the entity's spine
   (a period in which the entity has any row for the group) gets a filler row
   there with local_amount = 0, so the retranslation has a row to sit on. A
   filler whose retranslation is exactly 0 carries nothing and is dropped:
   no balance yet, or a rate that did not change (a Closing period translates
   at its year's last Regular period's rates, rate_period_map(), so its
   retranslation is always 0). #}
retranslated_keys as (
    select
        consolidation_group,
        data_area_id,
        main_account,
        partner_data_area_id,
        {{ dim_select(trailing=true) }}
        any(account_name) as account_name,
        any(account_type_name) as account_type_name,
        any(is_balance_sheet) as is_balance_sheet,
        any(is_pnl) as is_pnl,
        any(is_equity) as is_equity,
        any(uses_historical_rate) as uses_historical_rate,
        any(fx_method) as fx_method,
        min(toUInt32(fiscal_year) * 1000 + fiscal_period) as first_period_ord
    {# Aliased: ClickHouse would read the bare names in WHERE as the any()
       aliases above (ILLEGAL_AGGREGATION). #}
    from rated as r
    where r.is_balance_sheet = 1
      and r.is_equity = 0
      and r.fx_method not in ('average', 'historical')
    group by consolidation_group, data_area_id, main_account, partner_data_area_id{{ dim_group_by(leading=true) }}
),

{# The entity's spine per group: one row per period it has rows in, with the
   per-(group, entity, period) facts every row there shares: the currency pair,
   the ownership, the rates. #}
entity_spine as (
    select
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        any(accounting_currency) as accounting_currency,
        any(reporting_currency) as reporting_currency,
        any(ownership_pct) as ownership_pct,
        any(consolidation_method) as consolidation_method,
        any(closing_rate) as closing_rate,
        any(average_rate) as average_rate
    from rated
    group by consolidation_group, data_area_id, fiscal_year, fiscal_period
),

filler_candidates as (
    select
        k.consolidation_group as consolidation_group,
        k.data_area_id as data_area_id,
        s.fiscal_year as fiscal_year,
        s.fiscal_period as fiscal_period,
        k.main_account as main_account,
        k.account_name as account_name,
        k.account_type_name as account_type_name,
        k.is_balance_sheet as is_balance_sheet,
        k.is_pnl as is_pnl,
        k.is_equity as is_equity,
        k.partner_data_area_id as partner_data_area_id,
        {{ dim_select(prefix='k.', trailing=true) }}
        s.accounting_currency as accounting_currency,
        s.reporting_currency as reporting_currency,
        s.ownership_pct as ownership_pct,
        s.consolidation_method as consolidation_method,
        s.closing_rate as closing_rate,
        s.average_rate as average_rate,
        k.uses_historical_rate as uses_historical_rate,
        k.fx_method as fx_method
    from retranslated_keys as k
    inner join entity_spine as s
        on k.consolidation_group = s.consolidation_group
        and k.data_area_id = s.data_area_id
    where toUInt32(s.fiscal_year) * 1000 + s.fiscal_period > k.first_period_ord
),

{# Only the spine periods the key has no row in. #}
fillers as (
    select fc.*
    from filler_candidates as fc
    left anti join rated as r
        on fc.consolidation_group = r.consolidation_group
        and fc.data_area_id = r.data_area_id
        and fc.fiscal_year = r.fiscal_year
        and fc.fiscal_period = r.fiscal_period
        and fc.main_account = r.main_account
        and fc.partner_data_area_id = r.partner_data_area_id
        {{ dim_join_on('fc', 'r') }}
),

densified as (
    select
        consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account,
        account_name, account_type_name, is_balance_sheet, is_pnl, is_equity,
        partner_data_area_id,
        {{ dim_select(trailing=true) }}
        local_amount, accounting_currency, reporting_currency, ownership_pct, consolidation_method,
        closing_rate, average_rate, historical_equity_rate, translation_rate,
        uses_historical_rate, fx_method, is_retained_earnings, is_year_end_close,
        toUInt8(0) as is_filler
    from rated
    union all
    select
        consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account,
        account_name, account_type_name, is_balance_sheet, is_pnl, is_equity,
        partner_data_area_id,
        {{ dim_select(trailing=true) }}
        toDecimal128(0, 2) as local_amount, accounting_currency, reporting_currency, ownership_pct, consolidation_method,
        closing_rate, average_rate,
        cast(null as Nullable(Float64)) as historical_equity_rate,
        cast(closing_rate as Nullable(Float64)) as translation_rate,
        uses_historical_rate, fx_method,
        {# a filler is a balance sheet key that did not move: never the close #}
        toUInt8(0) as is_retained_earnings, toUInt8(0) as is_year_end_close,
        toUInt8(1) as is_filler
    from fillers
),

{# The windows run over every row of every period (period_filter is applied
   only in the final select), so a scoped build sees the key's history. #}
retranslated as (
    select
        *,
        if(
            is_balance_sheet = 1 and is_equity = 0 and fx_method not in ('average', 'historical'),
            toFloat64(sum(local_amount) over key_before)
                * (closing_rate - lagInFrame(closing_rate, 1, closing_rate) over key_all),
            0
        ) as retranslation_amount
    from densified
    window
        key_before as (
            partition by consolidation_group, data_area_id, main_account, partner_data_area_id{{ dim_partition_by(leading=true) }}
            order by fiscal_year, fiscal_period
            rows between unbounded preceding and 1 preceding
        ),
        key_all as (
            partition by consolidation_group, data_area_id, main_account, partner_data_area_id{{ dim_partition_by(leading=true) }}
            order by fiscal_year, fiscal_period
            rows between unbounded preceding and unbounded following
        )
),

{# konsolidat#259 (option #259-1, decided by Deepak Pai, 6 Oct 2026): the
   year-end close moves amounts that are already translated, so it creates no
   exchange difference.

   silver_tb_movements closes a period-end-balance year in the year's Closing
   period: each P&L key is reversed and the year's result moves into the
   retained-earnings account, as one lump on the blank key
   (is_year_end_close = 1). Translated as activity, the reversal goes at the
   period's average rate and retained earnings at its own declared rate, so
   the close left -(the year's P&L) x (average - closing) in that period's
   CTA, cancelling the year's CTA into retained earnings every year.

   P&L key, on its close row: the reversal returns the key's translated year
   to zero over its in-scope rows of the year,
       translated = (local + ytd_local_prior) x rate - ytd_translated_prior
   With a full reversal (local = -ytd_local_prior) that is exactly
   -ytd_translated_prior. For a part-year in scope (an acquisition) only the
   out-of-scope remainder translates at the row's rate.

   Retained earnings, on its close row (the lump key only): credited with the
   year's TRANSLATED result, whatever the account's fx_method declares
       translated = -sum(translated P&L close rows) + (local + sum(local P&L close rows)) x rate
   so the close period's translated rows net to zero and its CTA is 0 by
   construction. 3100's fx_method still governs every other movement of the
   account (opening balance, dividends, adjustments).

   Both adjustments ride in the row's retranslation_amount, so translated =
   local x translation_rate + retranslation_amount stays true on every row
   (assert_translated_amount_formula). A close an ERP posts itself carries no
   close mark and is translated as activity; assert_year_end_close_carries_no_cta
   names it. #}
close_pnl as (
    select
        *,
        if(
            is_year_end_close = 1 and is_pnl = 1,
            ifNull(
                toFloat64(sum(local_amount) over key_year_before) * translation_rate
                    - sum(toFloat64(local_amount) * translation_rate + retranslation_amount) over key_year_before,
                0),
            0
        ) as pnl_close_adjustment
    from retranslated
    window
        key_year_before as (
            partition by consolidation_group, data_area_id, main_account, partner_data_area_id{{ dim_partition_by(leading=true) }}, fiscal_year
            order by fiscal_period
            rows between unbounded preceding and 1 preceding
        )
),

closed as (
    select
        *,
        if(
            is_year_end_close = 1 and is_retained_earnings = 1 and partner_data_area_id = ''
            {%- for d in get_dimensions() %} and {{ d.name }} = ''{% endfor %},
            ifNull(
                sum(if(is_year_end_close = 1 and is_pnl = 1, toFloat64(local_amount), 0)) over close_period * translation_rate
                    - sum(if(is_year_end_close = 1 and is_pnl = 1,
                             ifNull(toFloat64(local_amount) * translation_rate, 0) + pnl_close_adjustment,
                             0)) over close_period,
                0),
            0
        ) as re_close_adjustment
    from close_pnl
    window
        close_period as (
            partition by consolidation_group, data_area_id, fiscal_year, fiscal_period
        )
),

adjusted as (
    select
        * except (retranslation_amount, pnl_close_adjustment, re_close_adjustment),
        {# the balance sheet retranslation (#257) and the close (#259) never
           fall on the same row: one is a non-equity balance sheet key, the
           other a P&L key or retained earnings #}
        retranslation_amount + pnl_close_adjustment + re_close_adjustment as translation_adjustment
    from closed
),

consolidated as (
    select
        *,
        {# Translated amount = local x translation_rate, plus the key's
           retranslation (konsolidat#257; 0 on every row that is not
           retranslated) #}
        local_amount * translation_rate + translation_adjustment as translated_amount,
        {# PRD-4: Group amount = translated x ownership_pct #}
        (local_amount * translation_rate + translation_adjustment) * ownership_pct as group_amount,
        {# PRD-4: NCI amount = translated x (1 - ownership_pct) #}
        (local_amount * translation_rate + translation_adjustment) * (1.0 - ownership_pct) as nci_amount
    from adjusted
    {# konsolidat#93: a missing governed rate fails the build loudly, never a
       0 or a 1.0 translation. throwIf takes a per-row condition (a constant
       would be folded and raise on every build). A failed run leaves its
       scope's slice empty until the next run (#162, accepted); the dbt test
       names the missing keys. Since konsolidat#257 this sees every period of
       the scope, not only the run's: a retranslation needs the earlier
       periods' closing rates too. #}
    where throwIf(translation_rate is null,
                  'konsolidat#93: a translated currency has no usable governed rate for its period: a Closing or Average rate is missing, duplicated, or zero, negative or not a finite number (konsol Group Exchange Rate). See assert_every_translated_currency_has_a_governed_rate.') = 0
      {# A filler that carries no retranslation carries nothing. #}
      and (is_filler = 0 or translation_adjustment != 0)
)

{# partner_data_area_id, then uses_historical_rate, then retranslation_amount,
   last: see the notes at the top. Each was added to an already-built table by
   an ALTER in the pre_hook, in that order, and ALTER ... ADD COLUMN appends at
   the end — so the select has to emit them in the same order or the
   positional append lands them swapped.
   konsolidat#257: the run's period filter applies here, after the windows. #}
select * except (partner_data_area_id, uses_historical_rate, translation_adjustment, fx_method,
                 is_retained_earnings, is_year_end_close, is_filler),
       partner_data_area_id,
       uses_historical_rate,
       {# konsolidat#259: the column also carries the year-end close's
          adjustment on P&L and retained-earnings close rows #}
       translation_adjustment as retranslation_amount
from consolidated
where 1 = 1
    {{ period_filter() }}
