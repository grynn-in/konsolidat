{{
    config(
        materialized='incremental',
        incremental_strategy='append',
        pre_hook="{% if is_incremental() %}DELETE FROM {{ this }} WHERE 1 = 1 {{ period_filter() }} {{ scope_filter() }}{% endif %}",
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

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
          from the governed group rates only (konsolidat#93 / konsol#103)
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
        {# PRD-10: Equity classification for historical rate lookup #}
        case when tb.account_type_name in ('Equity', 'Stockholders equity') then 1 else 0 end as is_equity,
        {{ dim_select(prefix='tb.') }},
        {# Signed double-entry movement (debit − credit), so the local TB sums
           to zero and the FX/CTA plug can balance it. Amounts arrive signed at
           the ERP boundary (models/staging/README.md). Silver splits them once
           into debit_amount / credit_amount by sign, and nothing after that
           infers a sign again. period_net_amount holds the same number
           (sum(debit) - sum(credit), per assert_period_net_equals_debit_minus_credit).
           It is no longer the positive magnitude #64 described. #}
        tb.period_debit - tb.period_credit as local_amount,
        ec.accounting_currency as accounting_currency,
        {{ build_date_from_year_period('tb.fiscal_year', 'tb.fiscal_period') }} as period_date
    from {{ ref('gold_trial_balance') }} as tb
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
    {# Orchestrator run filters (opt-in; no var => no predicate => full build).
       period_filter = single-period close; scope_filter = one entity/group.
       Applied here at the consolidation chokepoint so every downstream
       consolidation model (fully-consolidated TB, cash flow, YTD, NCI) inherits
       the slice, while foundational gold_trial_balance stays complete. #}
    where 1 = 1
        {{ period_filter('tb.fiscal_year', 'tb.fiscal_period') }}
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
   approved for it. No fallback of any kind. A translated currency with no
   approved rate stops the build (see `consolidated`), and
   assert_every_translated_currency_has_a_governed_rate names it. The old
   chain (Closing, else Default, else 1.0) translated whole ledgers at the 1.0
   parity rate without a word (#109). #}
governed_rates as (
    select
        from_currency,
        to_currency,
        fiscal_year,
        fiscal_period,
        {# One approved row per key: konsol refuses a second approval, and
           assert_governed_rate_grain_unique fails the build on a collision.
           anyIf over no rows is 0, so presence is counted, never inferred
           from the value. #}
        anyIf(toFloat64(rate), rate_type = 'Closing') as gov_closing,
        anyIf(toFloat64(rate), rate_type = 'Average') as gov_average,
        countIf(rate_type = 'Closing') as n_closing,
        countIf(rate_type = 'Average') as n_average
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
        etb.is_equity as is_equity,
        {{ dim_select(prefix='etb.') }},
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
            {# No approved Closing AND Average rate for this period: NULL here,
               and `consolidated` stops the build on it. Checked before the
               historical equity rate, so an equity tranche cannot hide a
               period the group never approved rates for. #}
            when gr.n_closing = 0 or gr.n_average = 0 then null
            when etb.is_equity = 1 and hr.historical_rate is not null then hr.historical_rate
            when etb.is_balance_sheet = 1 then gr.gov_closing
            when etb.is_pnl = 1 then gr.gov_average
            else gr.gov_closing
        end as translation_rate
    from entity_tb as etb
    {# One row per ancestor group: the fan-out here IS the multi-level
       consolidation. Period-keyed, because ownership is dated. #}
    inner join entity_ownership as eo
        on etb.data_area_id = eo.data_area_id
        and etb.fiscal_year = eo.fiscal_year
        and etb.fiscal_period = eo.fiscal_period
    {# join_use_nulls=0: a miss fills 0s, so n_closing / n_average = 0 is the
       "no approved rate" signal (never a NULL test across the join). #}
    left join governed_rates as gr
        on etb.accounting_currency = gr.from_currency
        and eo.reporting_currency = gr.to_currency
        and etb.fiscal_year = gr.fiscal_year
        and etb.fiscal_period = gr.fiscal_period
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

consolidated as (
    select
        *,
        {# Translated amount = local x translation_rate #}
        local_amount * translation_rate as translated_amount,
        {# PRD-4: Group amount = translated x ownership_pct #}
        local_amount * translation_rate * ownership_pct as group_amount,
        {# PRD-4: NCI amount = translated x (1 - ownership_pct) #}
        local_amount * translation_rate * (1.0 - ownership_pct) as nci_amount
    from rated
    {# konsolidat#93: a missing governed rate fails the build loudly, never a
       0 or a 1.0 translation. throwIf takes a per-row condition (a constant
       would be folded and raise on every build). A failed run leaves its
       scope's slice empty until the next run (#162, accepted); the dbt test
       names the missing keys. #}
    where throwIf(translation_rate is null,
                  'konsolidat#93: a translated currency has no approved governed Closing and Average rate for its period (konsol Group Exchange Rate). See assert_every_translated_currency_has_a_governed_rate.') = 0
)

select * from consolidated
