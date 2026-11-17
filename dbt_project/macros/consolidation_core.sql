{# konsol#348 S4 (W3): the consolidation core, one macro for the actuals model
   (gold_consolidated_trial_balance) and the consolidated budget model. It
   emits the CTEs {p}entity_tb .. {p}consolidated: the currency and chart
   joins, the per-ancestor-group ownership fan-out, governed-rate resolution,
   the balance sheet retranslation (konsolidat#257), the year-end close
   translation (konsolidat#259) and the translated / group / NCI amounts.
   Every rule, reference and comment inside is gold_consolidated_trial_balance's,
   moved here unchanged; the model keeps its config, pre_hooks and final select.
   Call it after at least one CTE, as `with x as (...), {{ ... }}`, and read
   {p}consolidated.

   source_cte          a CTE with one row per (entity, period, account, partner,
                       dimensions, grain_extra): data_area_id, fiscal_year,
                       fiscal_period, main_account, account_name,
                       account_type_name, is_balance_sheet, is_pnl,
                       partner_data_area_id, the dims, local_amount (signed,
                       debit - credit, Decimal) and is_year_end_close. The
                       statement flags come from the caller's source (decision
                       S4-Q6 (a), konsol#348): actuals take the trial balance
                       row's, the budget takes the chart's.
   dims                the dimension list (get_dimensions() for actuals,
                       get_budget_dimensions() for the budget).
   rate_set_predicate  a SQL predicate over the bare `rate_set` column, applied
                       to BOTH rate sources (group_exchange_rates,
                       historical_equity_rates): the actuals pass
                       actuals_rate_set_predicate() (the one set flagged
                       is_actuals in epm_staging.rate_sets, konsol#348 S4-Q7 a),
                       the budget passes its Cycle's set. Required: a default
                       would read every set, and two sets' rates for one key
                       are a duplicate the guard refuses (W2).
   ownership_cte       a CTE name, or a relation (ref('gold_entity_ownership')),
                       with gold_entity_ownership's columns, resolved on the
                       caller's own period spine: the actuals read the
                       materialised model; the budget resolves
                       ownership_resolution_ctes() on its budget periods, so a
                       budget period with no actuals row does not vanish.
   grain_extra         key columns the caller adds to the grain beyond (group,
                       entity, period, account, partner, dims): [] for actuals,
                       ['scenario_id', 'cycle', 'layer'] for the budget. Each
                       value is a consolidation of its own, so they are threaded
                       with the dims through every select, group by, join and
                       window partition below (`grain` = dims + grain_extra), and
                       alone (`extra`) into the entity spine and the close_period
                       window, which carry no dims. The one place that takes the
                       dims WITHOUT grain_extra is the retained-earnings lump key
                       in {p}closed: the close lump sits on the blank dimension
                       key of its own layer. assert_consolidation_core_grain_extra_is_a_partition
                       proves the threading: the same rows under two layers
                       consolidate, per layer, exactly as they do alone.
   scoped              whether the orchestrator's scope_filter narrows the
                       source (actuals yes, budget no). period_filter is the
                       caller's: the windows need every period of the scope.
   p                   a prefix for every CTE name, so one query can call the
                       core twice (the partition test does).
   rate_set_column     konsol#348 S4 (W4): none for the actuals (every row of
                       one call translates at the one set rate_set_predicate
                       selects, as before). The budget passes the name of a
                       source column holding EACH ROW's Rate Set (its Cycle's,
                       from epm_staging.budget_cycles): the set then joins the
                       rate key, so one model holds Cycles on different sets
                       and a key's rates are counted per set, never across
                       sets. rate_set_predicate still narrows the rate rows to
                       the sets in play (budget_rate_set_predicate(),
                       macros/budget_rates.sql). With it none, nothing below
                       changes: the three `if rate_set_column` blocks render
                       nothing.
   exits_relation      konsolidat#335 (#358 review F1, F2): the relation holding
                       the exit events, gold_ownership_exits' columns, or none.
                       Actuals: ref('gold_ownership_exits'); the re-entry stint
                       reset (spine_stints below) then applies, which is right
                       because gold_ownership_exit_journal derecognises the
                       pre-exit balance and the acquisition journal's line (0)
                       brings it back in. Budget: none (the default). A budget
                       posts no exit journal, so no reset: stint is 0 on every
                       row, as before #358, and the core renders no join to the
                       exits and no ref, so a tag:domain:scenarios build never
                       reads a model it does not build. What a budget does at
                       an exit is open (follow-up).

   Nothing here may add a column before partner_data_area_id of
   {p}consolidated: the actuals model appends by position (see its notes), and
   its final select orders partner_data_area_id, uses_historical_rate,
   retranslation_amount last. grain_extra columns sit after the dims, so a
   caller that passes any must place them in its own final select. #}
{% macro consolidation_core(source_cte, dims, rate_set_predicate, ownership_cte=none, grain_extra=[], scoped=true, p='', rate_set_column=none, exits_relation=none) %}
{%- if ownership_cte is none %}{{ exceptions.raise_compiler_error('consolidation_core: ownership_cte is required: a CTE or relation with gold_entity_ownership\'s columns, resolved on the caller\'s period spine') }}{% endif -%}
{%- if rate_set_predicate is none or (rate_set_predicate | trim) == '' or (rate_set_predicate | trim) == '1 = 1' %}{{ exceptions.raise_compiler_error('consolidation_core: rate_set_predicate is required: actuals_rate_set_predicate() for the actuals, the Cycle\'s set for a budget; a predicate that selects every set reads two rates for one key') }}{% endif -%}
{%- set extra = [] -%}
{%- for g in grain_extra %}{% do extra.append({'name': g}) %}{% endfor -%}
{%- set grain = dims + extra -%}
{{ p }}entity_tb as (
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
        {{ dim_select(dims=grain, prefix='tb.', trailing=true) }}
        {# The signed double-entry movement (debit - credit), as the caller's
           source CTE computes it (the actuals model: period_debit -
           period_credit of the partner trial balance), so the local TB sums to
           zero and the FX/CTA plug can balance it. Nothing here infers a sign. #}
        tb.local_amount as local_amount,
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
        {# konsol#348 (QA2 c): the date the historical equity rate is read as of, the period's declared
           window_end_date (macros/declared_periods.sql): a Regular period's own end, a Closing period's last
           Regular period's, an Opening period's the eve of the year. A period the calendar does not declare
           misses the LEFT JOIN and reads Date's default, 1970-01-01 (join_use_nulls=0): no tranche is that
           early, so it translates at the closing rate, and assert_trial_balance_period_declared names it.
           Read by the as-of join and never selected: no column may be added (positional append). #}
        dp.window_end_date as period_date
        {%- if rate_set_column %},
        {# konsol#348 S4 (W4): the row's own Rate Set (the budget's Cycle's);
           read by `rated`'s two rate joins and never selected into it. #}
        tb.{{ rate_set_column }} as rate_set
        {%- endif %}
    {# The caller's source CTE (its contract is in the header): the actuals
       model's is the partner-grained trial balance (konsol#159,
       gold_trial_balance_by_partner); the budget model's is the spread budget
       fact with the chart's statement flags. #}
    from {{ source_cte }} as tb
    {# konsolidat#369: one table read that always produces a plan step. ClickHouse
       24.8 sets a query's max_threads cap only on a storage read that produced a
       step; an empty MergeTree table becomes "Read from NullSource" and sets
       none. On a warehouse where EVERY table this reads is empty (a fresh site's
       first build) the plan therefore has no cap: the sort before each window
       step scatters its input into the pipeline's accumulated stream count
       instead of max_threads, the stacked windows multiply it (5 -> 10 -> 50
       window transforms for the actuals at max_threads 4, one stage more for
       the budget) and the executor starts a thread per stream: 163 threads at
       max_threads 8 for the actuals, CANNOT_SCHEDULE_TASK for the budget.
       system.one always produces a read step, so the cap holds: peak threads =
       max_threads + 1 on the same empty warehouse. One row, no column read,
       nothing in the result. tests/test_consolidation_core_thread_cap.py holds
       the measurements; query_plan_enable_multithreading_after_window_functions
       = 0 on the callers removes the resize AFTER each window and is still
       needed, but does not touch this scatter. #}
    cross join system.one
    {# konsol#110: the currency comes from silver_entity_currencies — konsol's
       Entity master, and since konsolidat#255 nothing else. This used to join
       silver_legal_entities, which knows only entities an ERP extracted, so a
       connector-less entity's submitted trial balance reached gold_trial_balance
       and then vanished here with nothing failing.

       Resolved currencies only. An entity with no Functional Currency
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
    left join {{ declared_periods() }} as dp
        on dp.fiscal_year = toUInt16(tb.fiscal_year)
        and dp.fiscal_period = toUInt16(tb.fiscal_period)
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
        {% if scoped %}{{ scope_filter('tb.data_area_id') }}{% endif %}
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
{{ p }}entity_ownership as (
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
    from {{ ownership_cte }} as eo
    left join {{ source('epm_gold', 'consolidation_groups') }} as grp
        on grp.consolidation_group = eo.consolidation_group
        and grp.data_area_id = ''
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
{{ p }}governed_rates as (
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
        {%- if rate_set_column %},
        {# konsol#348 S4 (W4): counted per set, so two Cycles' sets holding a
           rate for one key are two keys here, not a duplicate. #}
        rate_set
        {%- endif %}
    from {{ source('epm_staging', 'group_exchange_rates') }}
    where {{ rate_set_predicate }}
    group by from_currency, to_currency, fiscal_year, fiscal_period{% if rate_set_column %}, rate_set{% endif %}
),

{# Resolve per-row rate, ownership and translation_rate once.
   PRD-1 + PRD-10: translation rate depends on account type — equity → historical
   (fallback closing), BS → closing, PnL → average. A same-currency entity
   (accounting = reporting) ALWAYS translates at 1.0 regardless of what the rate
   table happens to contain (it carries scrambled same-currency rows, e.g.
   USD→USD ≠ 1 / CHF→CHF absent), so the local TB passes through unchanged and
   produces zero CTA. #}
{{ p }}rated as (
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
        {{ dim_select(dims=grain, prefix='etb.', trailing=true) }}
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
    from {{ p }}entity_tb as etb
    {# One row per ancestor group: the fan-out here IS the multi-level
       consolidation. Period-keyed, because ownership is dated. #}
    inner join {{ p }}entity_ownership as eo
        on etb.data_area_id = eo.data_area_id
        and etb.fiscal_year = eo.fiscal_year
        and etb.fiscal_period = eo.fiscal_period
    {# join_use_nulls=0: a miss fills 0s, so n_closing / n_average = 0 is the
       "no approved rate" signal (never a NULL test across the join).
       Keyed on the mapped rate period (konsolidat#199, row D9): the row's own
       period, or its year's last Regular period for a Closing period. #}
    left join {{ p }}governed_rates as gr
        on etb.accounting_currency = gr.from_currency
        and eo.reporting_currency = gr.to_currency
        and etb.rate_year = gr.fiscal_year
        and etb.rate_period = gr.fiscal_period
        {%- if rate_set_column %}
        and etb.rate_set = gr.rate_set
        {%- endif %}
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
            to_currency,
            rate_date,
            {# Nullable so an ASOF miss (period before the first tranche) yields
               NULL, not 0.0 — a non-nullable column would default to 0 on a
               LEFT-join miss and make the `hr.historical_rate is not null`
               fallback below wrongly translate equity at rate 0 (zeroing the
               balance) instead of closing_rate. Same defaulting trap the
               ownership block above guards against. #}
            cast(toFloat64(historical_rate) as Nullable(Float64)) as historical_rate
            {%- if rate_set_column %},
            rate_set
            {%- endif %}
        from {{ source('epm_staging', 'historical_equity_rates') }}
        where {{ rate_set_predicate }}
    ) as hr
        {# F2: on the entity's OWNING group, not the consolidating one. A
           historical equity rate is recorded once, under the node that owns the
           entity; keying on eo.consolidation_group after the multi-level
           fan-out missed at every ancestor above it, so the same equity account
           translated at the acquisition rate in the sub-group and silently fell
           through to the closing rate in the parent — two different CTAs for
           one entity.
           konsol#374 (option b; Deepak Pai, 7 Nov 2026): AND on the
           consolidating group's presentation currency. A rate converts the
           entity's currency into ONE currency (to_currency); a sub-group that
           presents in EUR and its parent that presents in USD each need their
           own rate for the same entity and account, and keyed without the
           currency the two tranches were one as-of series, the later one
           winning at both levels. A missing (group, currency) pair is a
           closing-rate fallback here and a named row in
           assert_declared_historical_has_a_rate, as a missing rate always was. #}
        on eo.owner_group = hr.consolidation_group
        and etb.data_area_id = hr.data_area_id
        and etb.main_account = hr.main_account
        and eo.reporting_currency = hr.to_currency
        {%- if rate_set_column %}
        and etb.rate_set = hr.rate_set
        {%- endif %}
        and etb.period_date >= hr.rate_date
    {# Line consolidation takes 'full' (100%, pair 2) and 'proportional' (the
       operator's share, a joint operation, IFRS 11.20, konsol#117 pair 3).
       PRD-14: equity-method entities are handled in a separate model. The
       method is the WEAKEST link on the chain, so an entity below an
       equity-held sub-group is excluded from that group's line consolidation
       too — while still line-consolidating into the sub-group itself.

       'none' is excluded as well: it is a real option on Ownership Period, and
       it is also gold_entity_ownership's catch-all rank for an unrecognised
       method — so a typo must not line-consolidate an entity at its full share
       with no NCI schedule row behind it (that model filters on 'full'; a
       proportional row needs none, its nci_amount is 0).

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
{{ p }}retranslated_keys as (
    select
        consolidation_group,
        data_area_id,
        main_account,
        partner_data_area_id,
        {{ dim_select(dims=grain, trailing=true) }}
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
    from {{ p }}rated as r
    where r.is_balance_sheet = 1
      and r.is_equity = 0
      and r.fx_method not in ('average', 'historical')
    group by consolidation_group, data_area_id, main_account, partner_data_area_id{{ dim_group_by(dims=grain, leading=true) }}
),

{# The entity's spine per group: one row per period it has rows in, with the
   per-(group, entity, period) facts every row there shares: the currency pair,
   the ownership, the rates. #}
{{ p }}entity_spine as (
    select
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        {{ dim_select(dims=extra, trailing=true) }}
        any(accounting_currency) as accounting_currency,
        any(reporting_currency) as reporting_currency,
        any(ownership_pct) as ownership_pct,
        any(consolidation_method) as consolidation_method,
        any(closing_rate) as closing_rate,
        any(average_rate) as average_rate
    from {{ p }}rated
    group by consolidation_group, data_area_id, fiscal_year, fiscal_period{{ dim_group_by(dims=extra, leading=true) }}
),

{{ p }}filler_candidates as (
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
        {{ dim_select(dims=grain, prefix='k.', trailing=true) }}
        s.accounting_currency as accounting_currency,
        s.reporting_currency as reporting_currency,
        s.ownership_pct as ownership_pct,
        s.consolidation_method as consolidation_method,
        s.closing_rate as closing_rate,
        s.average_rate as average_rate,
        k.uses_historical_rate as uses_historical_rate,
        k.fx_method as fx_method
    from {{ p }}retranslated_keys as k
    inner join {{ p }}entity_spine as s
        on k.consolidation_group = s.consolidation_group
        and k.data_area_id = s.data_area_id
        {{ dim_join_on('k', 's', dims=extra) }}
    where toUInt32(s.fiscal_year) * 1000 + s.fiscal_period > k.first_period_ord
),

{# Only the spine periods the key has no row in. #}
{{ p }}fillers as (
    select fc.*
    from {{ p }}filler_candidates as fc
    left anti join {{ p }}rated as r
        on fc.consolidation_group = r.consolidation_group
        and fc.data_area_id = r.data_area_id
        and fc.fiscal_year = r.fiscal_year
        and fc.fiscal_period = r.fiscal_period
        and fc.main_account = r.main_account
        and fc.partner_data_area_id = r.partner_data_area_id
        {{ dim_join_on('fc', 'r', dims=grain) }}
),

{{ p }}densified as (
    select
        consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account,
        account_name, account_type_name, is_balance_sheet, is_pnl, is_equity,
        partner_data_area_id,
        {{ dim_select(dims=grain, trailing=true) }}
        local_amount, accounting_currency, reporting_currency, ownership_pct, consolidation_method,
        closing_rate, average_rate, historical_equity_rate, translation_rate,
        uses_historical_rate, fx_method, is_retained_earnings, is_year_end_close,
        toUInt8(0) as is_filler
    from {{ p }}rated
    union all
    select
        consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account,
        account_name, account_type_name, is_balance_sheet, is_pnl, is_equity,
        partner_data_area_id,
        {{ dim_select(dims=grain, trailing=true) }}
        toDecimal128(0, {{ amount_scale() }}) as local_amount, accounting_currency, reporting_currency, ownership_pct, consolidation_method,
        closing_rate, average_rate,
        cast(null as Nullable(Float64)) as historical_equity_rate,
        cast(closing_rate as Nullable(Float64)) as translation_rate,
        uses_historical_rate, fx_method,
        {# a filler is a balance sheet key that did not move: never the close #}
        toUInt8(0) as is_retained_earnings, toUInt8(0) as is_year_end_close,
        toUInt8(1) as is_filler
    from {{ p }}fillers
),

{# konsolidat#335 (task X7): a key's retranslation history starts again at a
   re-entry. An exit (ownership_exits(): a bare link end) derecognises
   everything the group carried for the entity up to it
   (gold_ownership_exit_journal), and a later acquisition brings the balance
   back in at the acquisition period's closing rate (the acquisition journal's
   line (0)). Without a boundary the windows below would reach back across the
   gap and retranslate the derecognised pre-exit rows at 100% again (the
   joint_operation_gap shape: 50% carried, then 100% from the deal, plus
   cum_local(pre-exit) x (C(re-entry) - C(last pre-exit period))). stint
   counts the exits of (group, entity) whose first period out (out_fiscal_*,
   the period after the last one the entity was consolidated in) is at or
   before the row's period, so the rows of the exit period itself, which the
   exit journal reverses, close the old stint. 0 for an entity that never
   exited, so nothing else changes. A re-entry after a full Business Disposal
   is not an exit (ownership_exits()) and keeps one stint. An exit belongs to
   (group, entity), not to a grain_extra value, so every value of the extra
   grain counts the same exits; the spine carries `extra` as entity_spine
   does, and the join below keeps each value on its own spine rows. The
   events are read from gold_ownership_exits (the macro materialised once,
   task X22), not from the macro: one more copy of the ownership graph inside
   the core's pipeline is what that model takes out of every build. The
   caller passes them as exits_relation; with it none (the budget) neither
   CTE below joins anything and stint is 0 on every row (see the header). #}
{%- if exits_relation is not none %}
{{ p }}spine_stints as (
    select consolidation_group, data_area_id, fiscal_year, fiscal_period,
        {{ dim_select(dims=extra, trailing=true) }}
        sum(n) as stint
    from (
        select consolidation_group, data_area_id, fiscal_year, fiscal_period,
            {{ dim_select(dims=extra, trailing=true) }}
            toUInt32(0) as n
        from {{ p }}entity_spine

        union all

        select s.consolidation_group, s.data_area_id, s.fiscal_year, s.fiscal_period,
            {{ dim_select(dims=extra, prefix='s.', trailing=true) }}
            toUInt32(1)
        from {{ p }}entity_spine as s
        inner join {{ exits_relation }} as x
            on x.consolidation_group = s.consolidation_group
            and x.data_area_id = s.data_area_id
        where (toUInt16(x.out_fiscal_year), toUInt16(x.out_fiscal_period))
            <= (toUInt16(s.fiscal_year), toUInt16(s.fiscal_period))
    )
    group by consolidation_group, data_area_id, fiscal_year, fiscal_period{{ dim_group_by(dims=extra, leading=true) }}
),

{# Every row's period is on its entity's spine (fillers are spine periods), so
   the inner join drops nothing. #}
{{ p }}densified_stints as (
    select d.*, ss.stint as stint
    from {{ p }}densified as d
    inner join {{ p }}spine_stints as ss
        on ss.consolidation_group = d.consolidation_group
        and ss.data_area_id = d.data_area_id
        and ss.fiscal_year = d.fiscal_year
        and ss.fiscal_period = d.fiscal_period
        {{ dim_join_on('ss', 'd', dims=extra) }}
),
{%- else %}
{{ p }}densified_stints as (
    select d.*, toUInt32(0) as stint
    from {{ p }}densified as d
),
{%- endif %}

{# The windows run over every row of every period (period_filter is applied
   only in the final select), so a scoped build sees the key's history.

   konsolidat#335 (task X16): the windows partition by the KEY only, never by
   stint, so retranslated and close_pnl share one sort, as before X7. With
   stint in the partition, close_pnl (partition key, fiscal_year) needed a
   sort of its own; every window sort scatters its input by partition into
   max_threads x streams outputs, and the extra one grew the pipeline past
   the server's memory while building it, on an empty site (ClickHouse 24.8:
   the first TB-only build and the fixture gate's --prepare-ci both failed
   there). The stint boundary is applied by arithmetic instead:
   cum_local_before is the key's cumulative local amount before the row, and
   the anyLast over key_to_row is its value at the first row of the row's
   stint, so their difference is the cumulative within the stint. At a
   stint's first row it is 0, so that row retranslates nothing, whatever the
   previous row's rate; later rows of the stint follow rows of the same stint
   (stint never falls as the period rises). An entity that never exited has
   one stint starting at its first row, the subtracted value is 0, and the
   figures are unchanged. The key here is the threaded grain (dims +
   grain_extra), as in every other window of the core. stint is dropped after
   use: the core's output columns are unchanged. #}
{{ p }}stint_marks as (
    select
        *,
        sum(local_amount) over key_before as cum_local_before,
        toUInt8(stint != lagInFrame(stint, 1, toUInt32(4294967295)) over key_all) as is_stint_start
    from {{ p }}densified_stints
    window
        key_before as (
            partition by consolidation_group, data_area_id, main_account, partner_data_area_id{{ dim_partition_by(dims=grain, leading=true) }}
            order by fiscal_year, fiscal_period
            rows between unbounded preceding and 1 preceding
        ),
        key_all as (
            partition by consolidation_group, data_area_id, main_account, partner_data_area_id{{ dim_partition_by(dims=grain, leading=true) }}
            order by fiscal_year, fiscal_period
            rows between unbounded preceding and unbounded following
        )
),

{{ p }}retranslated as (
    select
        * except (cum_local_before, is_stint_start, stint),
        if(
            is_balance_sheet = 1 and is_equity = 0 and fx_method not in ('average', 'historical'),
            toFloat64(ifNull(
                cum_local_before - anyLast(if(is_stint_start = 1, cum_local_before, null)) over key_to_row,
                0))
                * (closing_rate - lagInFrame(closing_rate, 1, closing_rate) over key_all),
            0
        ) as retranslation_amount
    from {{ p }}stint_marks
    window
        key_to_row as (
            partition by consolidation_group, data_area_id, main_account, partner_data_area_id{{ dim_partition_by(dims=grain, leading=true) }}
            order by fiscal_year, fiscal_period
            rows between unbounded preceding and current row
        ),
        key_all as (
            partition by consolidation_group, data_area_id, main_account, partner_data_area_id{{ dim_partition_by(dims=grain, leading=true) }}
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
{{ p }}close_pnl as (
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
    from {{ p }}retranslated
    window
        key_year_before as (
            partition by consolidation_group, data_area_id, main_account, partner_data_area_id{{ dim_partition_by(dims=grain, leading=true) }}, fiscal_year
            order by fiscal_period
            rows between unbounded preceding and 1 preceding
        )
),

{{ p }}closed as (
    select
        *,
        if(
            is_year_end_close = 1 and is_retained_earnings = 1 and partner_data_area_id = ''
            {%- for d in dims %} and {{ d.name }} = ''{% endfor %},
            ifNull(
                sum(if(is_year_end_close = 1 and is_pnl = 1, toFloat64(local_amount), 0)) over close_period * translation_rate
                    - sum(if(is_year_end_close = 1 and is_pnl = 1,
                             ifNull(toFloat64(local_amount) * translation_rate, 0) + pnl_close_adjustment,
                             0)) over close_period,
                0),
            0
        ) as re_close_adjustment
    from {{ p }}close_pnl
    window
        close_period as (
            partition by consolidation_group, data_area_id, fiscal_year, fiscal_period{{ dim_partition_by(dims=extra, leading=true) }}
        )
),

{{ p }}adjusted as (
    select
        * except (retranslation_amount, pnl_close_adjustment, re_close_adjustment),
        {# the balance sheet retranslation (#257) and the close (#259) never
           fall on the same row: one is a non-equity balance sheet key, the
           other a P&L key or retained earnings #}
        retranslation_amount + pnl_close_adjustment + re_close_adjustment as translation_adjustment
    from {{ p }}closed
),

{{ p }}consolidated as (
    select
        *,
        {# Translated amount = local x translation_rate, plus the key's
           retranslation (konsolidat#257; 0 on every row that is not
           retranslated) #}
        local_amount * translation_rate + translation_adjustment as translated_amount,
        {# konsolidat#204 option (a), konsol#117 pair 2 (IFRS 10.B86): a controlled
           subsidiary (full) is consolidated line by line at 100%, whatever the
           group's share. konsol#117 pair 3 (IFRS 11.20): a joint operation
           (proportional) is carried at the operator's share, translated x
           ownership_pct. The where above drops equity and none. #}
        (local_amount * translation_rate + translation_adjustment)
            * if(consolidation_method = 'proportional', ownership_pct, 1.0) as group_amount,
        {# nci_amount of a controlled subsidiary (PRD-4, kept) = translated x
           (1 - ownership_pct), the ATTRIBUTION amount: the minority is one NCI
           line in equity, which konsol#117 pair 2 task K2 posts from this column.
           A joint operation has no minority (IFRS 11.20): 0, konsol#117 pair 3. #}
        if(consolidation_method = 'proportional', 0,
           (local_amount * translation_rate + translation_adjustment) * (1.0 - ownership_pct)) as nci_amount
    from {{ p }}adjusted
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
{% endmacro %}
