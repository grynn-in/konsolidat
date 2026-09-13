{#
    konsolidat#93 / konsol#103: the (from-currency, group reporting currency,
    fiscal year, fiscal period) keys gold_consolidated_trial_balance translates
    whose governed rates are not usable, with the reason:

      missing    no approved Closing AND Average rate;
      duplicate  more than one approved rate of one type (the model's anyIf
                 would pick one arbitrarily);
      invalid    a rate that is zero, negative or not a finite number (it
                 would translate the ledger to 0, flip its sign, or NaN it).

    Built from the model's own inputs and filters: resolved entity currencies,
    a complete ownership chain, line consolidation, the group's currency from
    its node. One definition, two users:
    * governed_rate_guard(): the model's FIRST pre_hook, scoped by the run's
      period and scope filters, so an unusable rate stops the run BEFORE the
      scope's DELETE, while the table is still intact;
    * assert_every_translated_currency_has_a_governed_rate (unscoped), which
      names each key and its reason.
    NOT IN / IN rather than a LEFT JOIN null test (join_use_nulls=0).
#}
{% macro governed_rate_gaps(scoped=true) %}
    with translated as (
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
    ),

    governed as (
        select
            from_currency as g_from,
            to_currency as g_to,
            toUInt16(fiscal_year) as g_fy,
            toUInt16(fiscal_period) as g_fp,
            countIf(rate_type = 'Closing') as n_closing,
            countIf(rate_type = 'Average') as n_average,
            countIf(not (isFinite(rate) and rate > 0)) as n_invalid
        from {{ source('epm_staging', 'group_exchange_rates') }}
        group by from_currency, to_currency, fiscal_year, fiscal_period
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
            ''
        ) as problem
    from translated
    where problem != ''
{% endmacro %}

{# One throwIf per reason: ClickHouse needs a constant message, so each names
   its own problem; the test names the keys. #}
{% macro governed_rate_guard() %}
    select
        throwIf(countIf(problem = 'missing') > 0,
            'konsolidat#93: a translated currency has no approved governed Closing and Average rate for its period (konsol Group Exchange Rate). Nothing was deleted. See assert_every_translated_currency_has_a_governed_rate.'),
        throwIf(countIf(problem = 'duplicate') > 0,
            'konsolidat#93: a translated currency has more than one approved governed rate of one type for its period. Nothing was deleted. See assert_every_translated_currency_has_a_governed_rate.'),
        throwIf(countIf(problem = 'invalid') > 0,
            'konsolidat#93: a governed rate a translated currency needs is zero, negative or not a finite number. Nothing was deleted. See assert_every_translated_currency_has_a_governed_rate.')
    from ({{ governed_rate_gaps(scoped=true) }})
{% endmacro %}
