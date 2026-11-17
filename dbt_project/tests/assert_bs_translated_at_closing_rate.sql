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

    konsolidat#335 (task X7): the balance restarts at a re-entry. An exit
    (ownership_exits(), a bare link end) derecognises what the group carried
    (gold_ownership_exit_journal) through its exit period, so from the exit's
    first period out (out_fiscal_*) on a key's balance counts only the rows at
    or after the latest such period up to p; the model's windows reset the
    same way (its spine_stints).
    konsolidat#335 (task X25): the acquisition journal's line (0) brings the
    balance at the re-entry at the re-entry period R's closing rate (the first
    spine period at or after that first period out), and the model
    retranslates it from then on. So the model's own rows from R to p carry
        sum(local_amount from R to p) x closing(p)
      + sum(local_amount before R) x (closing(p) - closing(R))
    the second term being the balance line (0) holds, retranslated from its
    rate to p's. With no exit, nothing is before R and the rule is the one
    above.
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

{# The latest exit of (group, entity) at or before each spine period, as an
   ordinal; 0 when none (UNION + GROUP BY: join_use_nulls = 0). #}
stint_start as (
    select consolidation_group, data_area_id, period_ord, max(exit_ord) as start_ord
    from (
        select consolidation_group, data_area_id, period_ord, toUInt32(0) as exit_ord
        from spine

        union all

        select s.consolidation_group, s.data_area_id, s.period_ord,
            toUInt32(x.out_fiscal_year) * 1000 + x.out_fiscal_period
        from spine as s
        inner join {{ ownership_exits() }} as x
            on x.consolidation_group = s.consolidation_group
            and x.data_area_id = s.data_area_id
        where toUInt32(x.out_fiscal_year) * 1000 + x.out_fiscal_period <= s.period_ord
    )
    group by consolidation_group, data_area_id, period_ord
),

{# The closing rate of the stint's first spine period (R), per spine period. #}
reentry_rate as (
    select st.consolidation_group as consolidation_group, st.data_area_id as data_area_id,
        st.period_ord as period_ord, argMin(s.closing_rate, s.period_ord) as reentry_closing_rate
    from stint_start as st
    inner join spine as s
        on s.consolidation_group = st.consolidation_group
        and s.data_area_id = st.data_area_id
    where s.period_ord >= st.start_ord and s.period_ord <= st.period_ord
    group by st.consolidation_group, st.data_area_id, st.period_ord
),
{# Balance to each spine period: every governed row at or before it, from the
   latest exit on, and the rows before it (before_stint_local). A key is checked from its first row on (no row before p
   means no balance yet). #}
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
        any(rr.reentry_closing_rate) as reentry_closing_rate,
        sum(if(g.period_ord >= st.start_ord, g.local_amount, 0)) as local_balance,
        sum(if(g.period_ord < st.start_ord, g.local_amount, 0)) as before_stint_local,
        sum(if(g.period_ord >= st.start_ord, g.translated_amount, 0)) as translated_balance
    from governed as g
    inner join spine as s
        on g.consolidation_group = s.consolidation_group
        and g.data_area_id = s.data_area_id
    inner join stint_start as st
        on st.consolidation_group = s.consolidation_group
        and st.data_area_id = s.data_area_id
        and st.period_ord = s.period_ord
    inner join reentry_rate as rr
        on rr.consolidation_group = s.consolidation_group
        and rr.data_area_id = s.data_area_id
        and rr.period_ord = s.period_ord
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
    before_stint_local,
    reentry_closing_rate,
    expected_translated_balance,
    translated_balance,
    concat(
        'account ', main_account, ' of entity ', data_area_id, ' in group ', consolidation_group,
        ' at FY', toString(fiscal_year), ' P', toString(fiscal_period),
        ': the translated balance is ', toString(round(translated_balance, 2)),
        ', but the local balance ', toString(round(local_balance, 2)),
        ' at the closing rate ', toString(closing_rate),
        if(before_stint_local != 0,
            concat(', plus the balance before the re-entry ', toString(round(before_stint_local, 2)),
                ' retranslated from the re-entry rate ', toString(reentry_closing_rate)),
            ''),
        ' is ', toString(round(expected_translated_balance, 2)),
        ' (konsolidat#257: a balance sheet balance is retranslated at each closing rate).'
    ) as problem
from (
    select *,
        local_balance * closing_rate
            + before_stint_local * (closing_rate - reentry_closing_rate) as expected_translated_balance
    from to_date
)
where abs(translated_balance - expected_translated_balance) > 0.01
