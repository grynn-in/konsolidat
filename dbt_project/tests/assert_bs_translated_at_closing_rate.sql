{#
    konsolidat#257: a balance-sheet balance is translated at the CLOSING rate of
    the reporting date (IAS 21.39(a)), not as the sum of each period's movement
    at that period's own closing rate.

    gold_consolidated_trial_balance keeps the movement grain: one row per
    (group, entity, period, account, partner, dimensions) carrying that period's
    translated movement. Every reader sums those movements to get a balance. So
    for every key of a balance sheet account that is translated at the closing
    rate, the translated movements summed to period p must equal the local
    movements summed to p times p's closing rate:

        | sum(translated_amount to p) - sum(local_amount to p) x closing(p) | <= 0.01

    Which keys: a balance sheet account (is_balance_sheet = 1) that is not
    equity (is_equity = 0; equity is never revalued, decided on #257 Q2, 6 Oct
    2026) and whose chart declares fx_method = 'closing' or declares nothing
    (an undeclared account translates at the closing rate). An account declared
    'average' or 'historical' is out of scope. The declaration comes from the
    chart (silver_main_accounts), not from the rate the row happens to carry.

    Which periods: EVERY period in which the entity has any row for the group
    (the entity's spine), from the key's first row on - not only the periods
    the key itself moved in. A balance that did not move in a period still has
    to be retranslated there; checking only the key's own rows would miss
    exactly that case.

    The closing rate of a spine period is read from the entity's rows in that
    period (one currency pair per entity and group, so one closing rate).
    Same-currency entities translate at 1.0 and are skipped.
#}

with declared as (
    select main_account_id, fx_method
    from {{ ref('silver_main_accounts') }}
),

{# The rows this rule governs. LEFT join: under join_use_nulls=0 an undeclared
   account reads fx_method = '', which is translated at closing. #}
governed as (
    select
        ctb.consolidation_group as consolidation_group,
        ctb.data_area_id as data_area_id,
        ctb.main_account as main_account,
        ctb.partner_data_area_id as partner_data_area_id,
        {{ dim_select(prefix='ctb.', trailing=true) }}
        toUInt32(ctb.fiscal_year) * 1000 + ctb.fiscal_period as period_ord,
        toFloat64(ctb.local_amount) as local_amount,
        ifNull(ctb.translated_amount, 0) as translated_amount
    from {{ ref('gold_consolidated_trial_balance') }} as ctb
    left join declared as d
        on ctb.main_account = d.main_account_id
    where ctb.accounting_currency != ctb.reporting_currency
      and ctb.is_balance_sheet = 1
      and ctb.is_equity = 0
      and d.fx_method not in ('average', 'historical')
),

{# The entity's spine in each group: every period it has any row, with that
   period's closing rate. #}
spine as (
    select
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        toUInt32(fiscal_year) * 1000 + fiscal_period as period_ord,
        any(closing_rate) as closing_rate
    from {{ ref('gold_consolidated_trial_balance') }}
    where accounting_currency != reporting_currency
    group by consolidation_group, data_area_id, fiscal_year, fiscal_period
),

{# Balance to each spine period: every governed row at or before it. A key is
   checked from its first row on (no row before p means no balance yet). #}
to_date as (
    select
        g.consolidation_group as consolidation_group,
        g.data_area_id as data_area_id,
        g.main_account as main_account,
        g.partner_data_area_id as partner_data_area_id,
        {{ dim_select(prefix='g.', trailing=true) }}
        s.fiscal_year as fiscal_year,
        s.fiscal_period as fiscal_period,
        any(s.closing_rate) as closing_rate,
        sum(g.local_amount) as local_balance,
        sum(g.translated_amount) as translated_balance
    from governed as g
    inner join spine as s
        on g.consolidation_group = s.consolidation_group
        and g.data_area_id = s.data_area_id
    where g.period_ord <= s.period_ord
    group by
        g.consolidation_group, g.data_area_id, g.main_account, g.partner_data_area_id,
        {{ dim_select(prefix='g.', trailing=true) }}
        s.fiscal_year, s.fiscal_period
)

select
    consolidation_group,
    data_area_id,
    fiscal_year,
    fiscal_period,
    main_account,
    partner_data_area_id,
    {{ dim_select(trailing=true) }}
    local_balance,
    closing_rate,
    local_balance * closing_rate as expected_translated_balance,
    translated_balance,
    concat(
        'account ', main_account, ' of entity ', data_area_id, ' in group ', consolidation_group,
        ' at FY', toString(fiscal_year), ' P', toString(fiscal_period),
        ': the translated balance is ', toString(round(translated_balance, 2)),
        ', but the local balance ', toString(round(local_balance, 2)),
        ' at the closing rate ', toString(closing_rate), ' is ', toString(round(local_balance * closing_rate, 2)),
        ' (konsolidat#257: a balance sheet balance is retranslated at each closing rate).'
    ) as problem
from to_date
where abs(translated_balance - local_balance * closing_rate) > 0.01
