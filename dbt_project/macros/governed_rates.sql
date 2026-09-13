{#
    konsolidat#93 / konsol#103: the (from-currency, group reporting currency,
    fiscal year, fiscal period) keys gold_consolidated_trial_balance translates
    that have NO approved governed Closing AND Average rate. Built from the
    model's own inputs and filters: resolved entity currencies, a complete
    ownership chain, line consolidation, the group's currency from its node.

    One definition, two users:
    * governed_rate_guard(): the model's FIRST pre_hook, scoped by the run's
      period and scope filters, so a missing rate stops the run BEFORE the
      scope's DELETE, while the table is still intact;
    * assert_every_translated_currency_has_a_governed_rate (unscoped), which
      names each gap.
    NOT IN rather than a LEFT JOIN null test (join_use_nulls=0).
#}
{% macro governed_rate_gaps(scoped=true) %}
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
      and (ec.accounting_currency, grp.reporting_currency, toUInt16(tb.fiscal_year), toUInt16(tb.fiscal_period)) not in (
          select from_currency, to_currency, toUInt16(fiscal_year), toUInt16(fiscal_period)
          from {{ source('epm_staging', 'group_exchange_rates') }}
          group by from_currency, to_currency, fiscal_year, fiscal_period
          having countIf(rate_type = 'Closing') > 0 and countIf(rate_type = 'Average') > 0
      )
{% endmacro %}

{% macro governed_rate_guard() %}
    select throwIf(count() > 0, 'konsolidat#93: a translated currency has no approved governed Closing and Average rate for its period (konsol Group Exchange Rate). Nothing was deleted. See assert_every_translated_currency_has_a_governed_rate.')
    from ({{ governed_rate_gaps(scoped=true) }})
{% endmacro %}
