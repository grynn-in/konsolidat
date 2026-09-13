{#
    konsolidat#93 / konsol#103. THE CONTRACT (decided 13 Sep 2026: one source
    of truth for FX rates, and it comes via konsol):
    epm_staging.group_exchange_rates.rate is the TRUE rate, units of
    to_currency per 1 from_currency, published by konsol. The warehouse never
    scales or inverts it (konsol divides out any "quoted per" factor before it
    publishes). silver_exchange_rates holds the ERP quotes, which feed only
    konsol's pre-fill. The magnitude check below is the net that stops an
    unscaled or double-scaled rate from ever being used.
#}

{#
    The (from-currency, group reporting currency, fiscal year, fiscal period)
    keys gold_consolidated_trial_balance translates whose governed rates are
    not usable, with the reason:

      missing      no approved Closing AND Average rate;
      duplicate    more than one approved rate of one type (the model's anyIf
                   would pick one arbitrarily);
      invalid      a rate that is zero, negative or not a finite number;
      implausible  a rate more than 10x from what the two currencies'
                   reference magnitudes imply (ISO Currency usd_log10, when
                   both are known): a #138-style scaling error, e.g. a rate
                   published without its "quoted per" factor divided out. A
                   currency with no reference value is not refused here (the
                   magnitude tests warn about it).

    Built from the model's own inputs and filters. One definition, two users:
    governed_rate_guard() (the model's FIRST pre_hook, scoped by the run's
    period and scope filters, so the run stops BEFORE the scope's DELETE) and
    assert_every_translated_currency_has_a_governed_rate (unscoped).
    NOT IN / IN rather than a LEFT JOIN null test (join_use_nulls=0).
#}
{# The (from, to, fy, fp) keys the model translates, with its own filters. #}
{% macro governed_translated_keys(scoped=true) %}
        select distinct
            ec.accounting_currency as from_currency,
            grp.reporting_currency as to_currency,
            toUInt16(tb.fiscal_year) as fy,
            toUInt16(tb.fiscal_period) as fp
        from {{ ref('gold_trial_balance') }} as tb
        inner join (
            select data_area_id, accounting_currency
            from {{ ref('silver_entity_currencies') }}
            where accounting_currency != ''
        ) as ec
            on ec.data_area_id = tb.data_area_id
        inner join {{ ref('gold_entity_ownership') }} as eo
            on eo.data_area_id = tb.data_area_id
            and eo.fiscal_year = tb.fiscal_year
            and eo.fiscal_period = tb.fiscal_period
        left join (
            select consolidation_group, reporting_currency
            from {{ source('epm_gold', 'consolidation_groups') }}
            where data_area_id = ''
        ) as grp
            on grp.consolidation_group = eo.consolidation_group
        where eo.consolidation_method not in ('equity', 'none')
          and eo.has_complete_chain = 1
          and ec.accounting_currency != grp.reporting_currency
          {% if scoped %}{{ period_filter('tb.fiscal_year', 'tb.fiscal_period') }} {{ scope_filter('tb.data_area_id') }}{% endif %}
{% endmacro %}

{% macro governed_rate_gaps(scoped=true) %}
    {%- set with_refs = fx_reference_column_present() -%}
    with translated as (
        {{ governed_translated_keys(scoped) }}
    ),

    {% if with_refs %}
    ref_mag as {{ fx_reference_magnitudes() }},
    {% endif %}

    gov_rows as (
        select
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
        from {{ source('epm_staging', 'group_exchange_rates') }} as g
        {% if with_refs %}
        left join ref_mag as f on f.currency_code = g.from_currency
        left join ref_mag as t on t.currency_code = g.to_currency
        {% endif %}
    ),

    governed as (
        select
            r_from as g_from, r_to as g_to, r_fy as g_fy, r_fp as g_fp,
            countIf(r_type = 'Closing') as n_closing,
            countIf(r_type = 'Average') as n_average,
            countIf(r_invalid) as n_invalid,
            countIf(r_implausible) as n_implausible
        from gov_rows
        group by r_from, r_to, r_fy, r_fp
    )

    select
        from_currency,
        to_currency,
        fy,
        fp,
        multiIf(
            (from_currency, to_currency, fy, fp) not in (
                select g_from, g_to, g_fy, g_fp from governed where n_closing > 0 and n_average > 0), 'missing',
            (from_currency, to_currency, fy, fp) in (
                select g_from, g_to, g_fy, g_fp from governed where n_closing > 1 or n_average > 1), 'duplicate',
            (from_currency, to_currency, fy, fp) in (
                select g_from, g_to, g_fy, g_fp from governed where n_invalid > 0), 'invalid',
            (from_currency, to_currency, fy, fp) in (
                select g_from, g_to, g_fy, g_fp from governed where n_implausible > 0), 'implausible',
            ''
        ) as problem
    from translated
    where problem != ''
{% endmacro %}

{# Stops the run, listing the unusable keys with their reasons: the first 50,
   sorted, then "... and N more" (the coverage test lists all). A run is
   refused whole: one missing rate stops a full build, by contract. ClickHouse's
   throwIf needs a constant message; a CAST of the message to UInt8 raises
   with the message itself in the error. The inner query always returns one
   row; the outer WHERE keeps it only when there is something to refuse, so
   the CAST is never evaluated on a clean run. #}
{% macro governed_rate_guard() %}
    select cast(concat(
        'konsolidat#93 refused before anything was deleted: ', toString(n),
        ' translated key(s) without a usable governed rate (konsol Group Exchange Rate): ', keys,
        if(n > 50, concat(' ... and ', toString(n - 50), ' more (assert_every_translated_currency_has_a_governed_rate lists all)'), ''),
        '. Reasons: missing = no approved Closing and Average rate; duplicate = more than one approved rate of a type;',
        ' invalid = zero, negative or not finite; implausible = more than 10x from the reference magnitudes (check the quoted-per factor).'
    ) as UInt8)
    from (
        select
            count() as n,
            arrayStringConcat(arraySlice(arraySort(groupArray(
                concat(from_currency, '->', to_currency, ' FY', toString(fy), ' P', toString(fp), ' ', problem))), 1, 50), '; ') as keys
        from ({{ governed_rate_gaps(scoped=true) }})
    )
    where n > 0
{% endmacro %}

{#
    deploy.sh's pre-step-5 check, run through the dbt_init service (inside the
    compose network) with `dbt show --inline "{{ fx_precheck() }}"`. The same
    macros as the guard, so it includes every reason (missing, duplicate,
    invalid, implausible) and cannot drift from it. One row per line, each
    starting with a marker deploy.sh greps:
      FX_NOTHING_BUILT        no trial balance or ownership built yet
      FX_TABLE_MISSING <n>    epm_staging.group_exchange_rates does not exist;
                              n translated foreign-currency keys need it
      FX_GAPS_TOTAL <n>       n translated keys have no usable rate, then
      FX_GAP <key> <reason>   one line per key, sorted
#}
{% macro fx_precheck() %}
-- depends_on: {{ ref('gold_trial_balance') }} {{ ref('silver_entity_currencies') }} {{ ref('gold_entity_ownership') }} {{ source('epm_gold', 'consolidation_groups') }} {{ source('epm_staging', 'group_exchange_rates') }} {{ source('epm_gold', 'currencies') }}
{%- set ger, tb, eo = none, none, none -%}
{%- if execute -%}
    {%- set g = source('epm_staging', 'group_exchange_rates') -%}
    {%- set ger = adapter.get_relation(database=none, schema=g.schema, identifier=g.identifier) -%}
    {%- set t = ref('gold_trial_balance') -%}
    {%- set tb = adapter.get_relation(database=none, schema=t.schema, identifier=t.identifier) -%}
    {%- set o = ref('gold_entity_ownership') -%}
    {%- set eo = adapter.get_relation(database=none, schema=o.schema, identifier=o.identifier) -%}
{%- endif %}
{% if not execute or tb is none or eo is none %}
select 0 as o, 'FX_NOTHING_BUILT' as fx_check
{% elif ger is none %}
select 0 as o, concat('FX_TABLE_MISSING ', toString(count())) as fx_check from ({{ governed_translated_keys(scoped=false) }})
{% else %}
select o, fx_check from (
    select 0 as o, concat('FX_GAPS_TOTAL ', toString(count())) as fx_check
    from ({{ governed_rate_gaps(scoped=false) }})
    union all
    select 1 as o, concat('FX_GAP ', from_currency, '->', to_currency, ' FY', toString(fy), ' P', toString(fp), ' ', problem) as fx_check
    from ({{ governed_rate_gaps(scoped=false) }})
)
order by o, fx_check
{% endif %}
{% endmacro %}
