{#
    konsol#348 S4 (W4, W5): the consolidated budget's inputs and its rate guard.

    A budget translates at the Rate Set its Budget Cycle declares (BUD-3;
    S4-Q1 c, S4-Q2 a), read from epm_staging.budget_cycles, konsol's
    write-through of the APPROVED Cycles. Never at the actuals set, and never
    at 1.0: a budget key whose Cycle's set has no usable rate stops the budget
    build by name (budget_rate_guard, the model's pre_hook), and only the
    budget build. The actuals guard (governed_rate_guard, macros/
    governed_rates.sql) keys on gold_trial_balance and the actuals set, so a
    missing budget rate never stops gold_consolidated_trial_balance, and a
    missing actuals rate never stops the budget.

    One definition, three users: budget_rate_gaps() is read by the guard
    (pre_hook), by assert_budget_translated_currency_has_a_governed_rate (the
    singular test that lists every gap) and, through
    budget_consolidation_inputs(), by the model itself, so the keys the guard
    requires are exactly the keys the model translates.
#}

{#
    The rate rows a budget build reads: every set an approved Cycle declares.
    This is the budget's `rate_set_predicate` for consolidation_core (which
    requires one): it narrows the rate tables to the sets in play, and the
    core's `rate_set_column` then keys each row's rate on its own Cycle's set,
    so two Cycles' sets holding a rate for one (from, to, year, period) are two
    keys, not a duplicate. `column` is the rate_set column as the caller's
    query sees it (`rate_set` bare, `g.rate_set` under an alias).
#}
{% macro budget_rate_set_predicate(column='rate_set') -%}
{{ column }} in (select rate_set from {{ source('epm_staging', 'budget_cycles') }})
{%- endmacro %}

{#
    The budget fact as the consolidation reads it, and its period spine. Emits
    two CTEs, {p}budget_fact and {p}budget_periods; call it after `with`, as
    `with {{ budget_consolidation_inputs() }}, ...`.

    {p}budget_fact   gold_spread_budget joined to the APPROVED Cycles
                     (epm_staging.budget_cycles, on the Cycle's name), carrying
                     the Cycle's rate_set. A fact row whose Cycle is not
                     approved is not consolidated; assert_budget_cycle_is_approved
                     (warn) names it, so nothing leaves silently.
    {p}budget_periods  (omitted with with_periods=false, for a caller that only
                     needs the fact) the distinct (entity, fiscal_year, fiscal_period) the
                     BUDGET has rows in, with the dates konsol's calendar
                     declares for the period (declared_periods()), in the shape
                     ownership_resolution_ctes() takes. This is the spine the
                     budget's ownership is resolved on: gold_entity_ownership's
                     spine is the ACTUALS' periods, so a budget period with no
                     trial balance row (next year's budget, entered before the
                     year starts) has no ownership there and vanished from an
                     ownership join on it. gold_budget_entity_ownership
                     materialises the resolution on this spine (konsolidat#369).
                     A budget period the calendar does
                     not declare is dropped by the inner join and named by
                     assert_budget_period_declared.
#}
{% macro budget_consolidation_inputs(p='', with_periods=true) %}
{{ p }}budget_fact as (
    select
        b.scenario_id as scenario_id,
        b.cycle as cycle,
        b.layer as layer,
        b.data_area_id as data_area_id,
        toUInt16(b.fiscal_year) as fiscal_year,
        toUInt16(b.fiscal_period) as fiscal_period,
        b.main_account as main_account,
        {{ dim_select(dims=get_budget_dimensions(), prefix='b.', trailing=true) }}
        b.currency as currency,
        b.period_amount as period_amount,
        bc.rate_set as rate_set
    from {{ ref('gold_spread_budget') }} as b
    inner join (
        select name, rate_set
        from {{ source('epm_staging', 'budget_cycles') }}
    ) as bc
        on bc.name = b.cycle
)
{%- if with_periods %},

{{ p }}budget_periods as (
    select distinct
        f.data_area_id as data_area_id,
        f.fiscal_year as fiscal_year,
        f.fiscal_period as fiscal_period,
        dp.window_start_date as period_start_date,
        dp.window_end_date as period_date
    from {{ p }}budget_fact as f
    inner join {{ declared_periods() }} as dp
        on dp.fiscal_year = f.fiscal_year
        and dp.fiscal_period = f.fiscal_period
)
{%- endif %}
{% endmacro %}

{#
    The (scenario, cycle, rate set, from-currency, group reporting currency,
    rate year, rate period) keys the consolidated budget translates whose rates
    in the CYCLE'S set are not usable, with the reason:

      missing      no approved Closing AND Average rate in that set;
      duplicate    more than one approved rate of one type in that set;
      invalid      a rate that is zero, negative or not a finite number;
      implausible  more than 10x from the two currencies' reference magnitudes
                   (ISO Currency usd_log10, when both are known).

    The keys are the model's own: the budget fact of the approved Cycles, the
    entity's currency (silver_entity_currencies), the groups the entity
    line-consolidates into at that period (gold_budget_entity_ownership, the
    ownership the model consolidates on; konsolidat#369), the group's reporting
    currency, same-currency rows excluded, the period mapped through
    rate_period_map() (a Closing period's rates are its year's last Regular
    period's, konsolidat#199 row D9). The rate rows are the Cycles' sets only
    (budget_rate_set_predicate) and are counted per set. NOT IN / IN rather
    than a LEFT JOIN null test (join_use_nulls=0). Unscoped: the budget model
    takes no orchestrator scope.
#}
{% macro budget_rate_gaps() %}
    {%- set with_refs = fx_reference_column_present() %}
    with {{ budget_consolidation_inputs(p='gap_', with_periods=false) }},

    translated as (
        select distinct
            f.scenario_id as scenario_id,
            f.cycle as cycle,
            f.rate_set as rate_set,
            ec.accounting_currency as from_currency,
            grp.reporting_currency as to_currency,
            if(rpm.mapped = 1, rpm.rate_year, f.fiscal_year) as fy,
            if(rpm.mapped = 1, rpm.rate_period, f.fiscal_period) as fp
        from gap_budget_fact as f
        left join {{ rate_period_map() }} as rpm
            on rpm.fiscal_year = f.fiscal_year
            and rpm.fiscal_period = f.fiscal_period
        inner join (
            select data_area_id, accounting_currency
            from {{ ref('silver_entity_currencies') }}
            where accounting_currency != ''
        ) as ec
            on ec.data_area_id = f.data_area_id
        inner join {{ ref('gold_budget_entity_ownership') }} as eo
            on eo.data_area_id = f.data_area_id
            and eo.fiscal_year = f.fiscal_year
            and eo.fiscal_period = f.fiscal_period
        left join (
            select consolidation_group, reporting_currency
            from {{ source('epm_gold', 'consolidation_groups') }}
            where data_area_id = ''
        ) as grp
            on grp.consolidation_group = eo.consolidation_group
        where eo.consolidation_method not in ('equity', 'none')
          and eo.has_complete_chain = 1
          and ec.accounting_currency != grp.reporting_currency
    ),

    {% if with_refs %}
    ref_mag as {{ fx_reference_magnitudes() }},
    {% endif %}

    gov_rows as (
        select
            g.rate_set as r_set,
            g.from_currency as r_from,
            g.to_currency as r_to,
            toUInt16(g.fiscal_year) as r_fy,
            toUInt16(g.fiscal_period) as r_fp,
            g.rate_type as r_type,
            not (isFinite(g.rate) and g.rate > 0) as r_invalid,
            {% if with_refs %}
            (not r_invalid
             and g.from_currency in (select currency_code from ref_mag)
             and g.to_currency in (select currency_code from ref_mag)
             and {{ fx_is_implausible('g.rate', 'f.usd_log10', 't.usd_log10') }}) as r_implausible
            {% else %}
            false as r_implausible
            {% endif %}
        from (
            {# the Cycles' sets only, before anything is counted #}
            select from_currency, to_currency, fiscal_year, fiscal_period, rate_type, rate, rate_set
            from {{ source('epm_staging', 'group_exchange_rates') }} as g
            where {{ budget_rate_set_predicate('g.rate_set') }}
        ) as g
        {% if with_refs %}
        left join ref_mag as f on f.currency_code = g.from_currency
        left join ref_mag as t on t.currency_code = g.to_currency
        {% endif %}
    ),

    governed as (
        select
            r_set as g_set, r_from as g_from, r_to as g_to, r_fy as g_fy, r_fp as g_fp,
            countIf(r_type = 'Closing') as n_closing,
            countIf(r_type = 'Average') as n_average,
            countIf(r_invalid) as n_invalid,
            countIf(r_implausible) as n_implausible
        from gov_rows
        group by r_set, r_from, r_to, r_fy, r_fp
    )

    select
        scenario_id,
        cycle,
        rate_set,
        from_currency,
        to_currency,
        fy,
        fp,
        multiIf(
            (rate_set, from_currency, to_currency, fy, fp) not in (
                select g_set, g_from, g_to, g_fy, g_fp from governed where n_closing > 0 and n_average > 0), 'missing',
            (rate_set, from_currency, to_currency, fy, fp) in (
                select g_set, g_from, g_to, g_fy, g_fp from governed where n_closing > 1 or n_average > 1), 'duplicate',
            (rate_set, from_currency, to_currency, fy, fp) in (
                select g_set, g_from, g_to, g_fy, g_fp from governed where n_invalid > 0), 'invalid',
            (rate_set, from_currency, to_currency, fy, fp) in (
                select g_set, g_from, g_to, g_fy, g_fp from governed where n_implausible > 0), 'implausible',
            ''
        ) as problem
    from translated
    where problem != ''
{% endmacro %}

{#
    gold_consolidated_budget_tb's pre_hook. Stops the budget build, naming
    every unusable key (scenario, Cycle, Rate Set, currency pair, rate period,
    reason): the first 50, sorted, then "... and N more" (the singular test
    lists all). The budget is refused whole: one missing rate in one Cycle's
    set stops the budget build, by contract, and nothing falls back to the
    actuals set or to 1.0. The model is a table, so a refused build leaves the
    previous table as it was. ClickHouse's throwIf needs a constant message; a
    CAST of the message to UInt8 raises with the message itself in the error.
    The inner query always returns one row; the outer WHERE keeps it only when
    there is something to refuse, so the CAST is never evaluated on a clean
    run, and on empty budget tables (the TB-only first build) there is nothing
    to refuse.

    No set-count rule here: the budget does not read the actuals set, and a
    Cycle without a set cannot be approved in konsol (BUD-3). The throwIf in
    the core's `consolidated` stays as the second line of defence.
#}
{% macro budget_rate_guard() %}
    select cast(
        concat(
            'konsol#348 S4 refused before the consolidated budget was replaced: ', toString(n),
            ' budget key(s) with no usable governed rate in the Rate Set its Cycle declares (konsol Group Exchange Rate): ', keys,
            if(n > 50, concat(' ... and ', toString(n - 50), ' more (assert_budget_translated_currency_has_a_governed_rate lists all)'), ''),
            '. No fallback: the actuals set is not read for a budget, and no rate is 1.0.',
            ' Reasons: missing = no approved Closing and Average rate in that set; duplicate = more than one approved rate of a type;',
            ' invalid = zero, negative or not finite; implausible = more than 10x from the reference magnitudes (check the quoted-per factor).'
        ) as UInt8)
    from (
        select
            count() as n,
            arrayStringConcat(arraySlice(arraySort(groupArray(
                concat(scenario_id, ' ', cycle, ' set ', rate_set, ' ', from_currency, '->', to_currency,
                       ' FY', toString(fy), ' P', toString(fp), ' ', problem))), 1, 50), '; ') as keys
        from ({{ budget_rate_gaps() }})
    ) as gaps
    where n > 0
{% endmacro %}
