{{
    config(
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# Intercompany reconciliation: one row per PAIR and period, the two sides of
   one intercompany balance (konsolidat#148, konsol#159).

   A side is (entity, partner, account): an entity's amount on a flagged
   intercompany account with one partner. Its other side is (partner, entity,
   counterpart), what the partner books against it. The pair is keyed with its
   lexically smaller side as `a`, so both sides land on one row whichever
   entity reports first. A side with nothing booked counts as 0, so a partner
   that booked nothing leaves the whole amount as the difference.

   Decided 13 Sep 2026:
   - Decisions 1 and 2: the counterparty is the partner on each row, never
     guessed. A row with no partner is not paired; gold_ic_unmatched lists it.
   - Decision 12: pairs match on the FULL translated amount (balance_a,
     balance_b = translated_amount at 100%), never the ownership-weighted
     group_amount, so a difference is a real mismatch and never ownership.
     group_balance_* and share_* say what the group view holds of each side;
     gold_ic_eliminations eliminates each side at that share, sends the
     minority owners' portion to the NCI line, and eliminates the NCI view's
     share of the same balance there.
   - Decision 13: one intercompany-difference account per group, and each
     difference is labelled by cause (difference_cause). The rule:
       * 'none'    when |difference| < 0.005;
       * 'fx'      when the sides' functional currencies differ. A trial
                   balance carries no transaction currency or booking rate, so
                   such a difference cannot be shown to be a booking error;
       * 'booking' when they share a currency and the local amounts do not
                   net to zero (the same currency makes them directly
                   comparable);
       * 'fx'      when they share a currency and the local amounts DO net
                   to zero. The difference is then translation alone: the
                   same amount translated at different periods' rates.
     Only a booking difference counts against the tolerance. An fx difference
     is reported (match_status 'fx_difference') and never over_tolerance.
   - Decision 14: a balance-sheet pair (receivable, payable, loan) compares
     the balance to date; a P&L pair compares the period's movement.

   Membership (#175 re-review M1). A pair exists in a group only while BOTH
   entities line-consolidate into it (gold_entity_ownership):
   - A balance-sheet side's balance to date is everything that side has
     booked in the group view, including its rows with this partner from
     before the partner joined (a receivable from a company later acquired).
     So the first period of joint membership compares the balances AT
     joining, not the movements since. That row always exists
     (pair_event 'joined'), whether or not anything moved.
   - The first period after a partner's ownership has ended (every ownership
     period of it ended before that period's date), while the other side is
     still in the group, is a 'left' row. Its values are 0, so every
     elimination posted to date is reversed there: the balance is no longer
     intragroup.
   - A period in which one side merely has no data (it is still owned) gets
     no row. The pair carries its last position; nothing is reversed.
   - What the warehouse does not hold: an acquired entity's own balances from
     before it joined. Its pre-acquisition rows fall outside its ownership
     window, so gold_consolidated_trial_balance never carries them. Until
     its trial balance for the joining period carries its opening balances,
     an intercompany balance that existed at acquisition shows as a booking
     difference from the joining period. #}

{# konsol#159 adds the group's difference account and tolerance to
   epm_gold.consolidation_groups (ensure_reference_tables on every migrate;
   init-db.sql on a fresh volume). Read only if present, so this model deploys
   in either order with konsol: without them, no difference is booked. #}
{% set diff_account_expr = "''" %}
{% set tolerance_expr = "toFloat64(0)" %}
{% if execute %}
    {% set group_columns = adapter.get_columns_in_relation(source('epm_gold', 'consolidation_groups')) | map(attribute='name') | list %}
    {% if 'ic_difference_account' in group_columns %}
        {% set diff_account_expr = 'ic_difference_account' %}
    {% endif %}
    {% if 'ic_difference_tolerance' in group_columns %}
        {% set tolerance_expr = 'toFloat64(ic_difference_tolerance)' %}
    {% endif %}
{% endif %}

{% set pair = "consolidation_group, entity_a, account_a, entity_b, account_b" %}
{% set to_date = "partition by " ~ pair ~ " order by fiscal_year, fiscal_period rows between unbounded preceding and current row" %}

with ic_accounts as (
    {{ ic_account_map() }}
),

members as (
    select distinct consolidation_group, data_area_id, fiscal_year, fiscal_period
    from {{ ref('gold_entity_ownership') }}
    where has_complete_chain = 1
      and consolidation_method not in ('equity', 'none')
),

{# when an entity's ownership has ended: the latest end of its ownership
   periods, when none is open. An open period ends '9999-12-31', stored as
   ClickHouse's largest Date. #}
ownership_ends as (
    select data_area_id as ended_entity, max(end_date) as last_end
    from {{ source('epm_staging', 'ownership_periods') }}
    group by data_area_id
    having max(end_date) < toDate('2149-01-01')
),

{# each side's MOVEMENT in the period: local, translated (100%), group share.
   Not Nullable: translated_amount is (the historical-rate join), and a side
   with nothing booked must count as 0, not make the difference NULL. Every
   period the side is in the group view, whether or not its partner is yet. #}
sides as (
    select
        ctb.consolidation_group as consolidation_group,
        ctb.fiscal_year as fiscal_year,
        ctb.fiscal_period as fiscal_period,
        ctb.data_area_id as entity,
        ctb.partner_data_area_id as partner,
        ctb.main_account as account,
        ica.counterpart as counterpart,
        max(ctb.is_balance_sheet) as side_is_bs,
        ifNull(toFloat64(sum(ctb.local_amount)), 0) as mov_local,
        ifNull(toFloat64(sum(ctb.translated_amount)), 0) as mov_translated,
        ifNull(toFloat64(sum(ctb.group_amount)), 0) as mov_group
    from {{ ref('gold_consolidated_trial_balance') }} as ctb
    inner join ic_accounts as ica
        on ctb.main_account = ica.account
    where ctb.partner_data_area_id != ''
      and ctb.partner_data_area_id != ctb.data_area_id
    group by
        ctb.consolidation_group,
        ctb.fiscal_year,
        ctb.fiscal_period,
        ctb.data_area_id,
        ctb.partner_data_area_id,
        ctb.main_account,
        ica.counterpart
),

keyed as (
    select
        consolidation_group,
        fiscal_year,
        fiscal_period,
        side_is_bs,
        mov_local,
        mov_translated,
        mov_group,
        tuple(entity, account) < tuple(partner, counterpart) as is_a,
        if(is_a, entity, partner) as entity_a,
        if(is_a, account, counterpart) as account_a,
        if(is_a, partner, entity) as entity_b,
        if(is_a, counterpart, account) as account_b
    from sides
),

pair_moves as (
    select
        consolidation_group,
        fiscal_year,
        fiscal_period,
        entity_a,
        account_a,
        entity_b,
        account_b,
        max(side_is_bs) as row_is_bs,
        sumIf(mov_local, is_a) as mov_local_a,
        sumIf(mov_local, not is_a) as mov_local_b,
        sumIf(mov_translated, is_a) as mov_translated_a,
        sumIf(mov_translated, not is_a) as mov_translated_b,
        sumIf(mov_group, is_a) as mov_group_a,
        sumIf(mov_group, not is_a) as mov_group_b
    from keyed
    group by consolidation_group, fiscal_year, fiscal_period, entity_a, account_a, entity_b, account_b
),

pair_keys as (
    select distinct consolidation_group, entity_a, account_a, entity_b, account_b
    from pair_moves
),

{# every period at least one side is in the group #}
side_periods as (
    select
        pk.consolidation_group as consolidation_group, pk.entity_a as entity_a, pk.account_a as account_a,
        pk.entity_b as entity_b, pk.account_b as account_b,
        m.fiscal_year as fiscal_year, m.fiscal_period as fiscal_period,
        toUInt8(1) as a_in, toUInt8(0) as b_in
    from pair_keys as pk
    inner join members as m
        on m.consolidation_group = pk.consolidation_group and m.data_area_id = pk.entity_a
    union all
    select
        pk.consolidation_group, pk.entity_a, pk.account_a, pk.entity_b, pk.account_b,
        m.fiscal_year, m.fiscal_period,
        toUInt8(0), toUInt8(1)
    from pair_keys as pk
    inner join members as m
        on m.consolidation_group = pk.consolidation_group and m.data_area_id = pk.entity_b
),

spine as (
    select
        consolidation_group, entity_a, account_a, entity_b, account_b, fiscal_year, fiscal_period,
        max(a_in) as a_member,
        max(b_in) as b_member,
        {{ build_date_from_year_period('fiscal_year', 'fiscal_period') }} as period_date
    from side_periods
    group by consolidation_group, entity_a, account_a, entity_b, account_b, fiscal_year, fiscal_period
),

spine_state as (
    select
        s.consolidation_group as consolidation_group, s.entity_a as entity_a, s.account_a as account_a,
        s.entity_b as entity_b, s.account_b as account_b,
        s.fiscal_year as fiscal_year, s.fiscal_period as fiscal_period,
        toUInt8(s.a_member = 1 and s.b_member = 1) as is_live,
        {# join_use_nulls=0: an entity with an open ownership period has no
           ownership_ends row, and comes back as 1970-01-01 #}
        toUInt8(
            (s.a_member = 1 and s.b_member = 0 and eb.last_end > toDate('1970-01-01') and s.period_date > eb.last_end)
            or (s.a_member = 0 and s.b_member = 1 and ea.last_end > toDate('1970-01-01') and s.period_date > ea.last_end)
        ) as is_out
    from spine as s
    left join ownership_ends as ea on ea.ended_entity = s.entity_a
    left join ownership_ends as eb on eb.ended_entity = s.entity_b
),

spine_marked as (
    select
        *,
        lagInFrame(is_live, 1, toUInt8(0)) over ({{ to_date }}) as prev_live
    from spine_state
    where is_live = 1 or is_out = 1
),

combined as (
    select
        consolidation_group, entity_a, account_a, entity_b, account_b, fiscal_year, fiscal_period,
        toUInt8(row_is_bs) as row_is_bs,
        mov_local_a, mov_local_b, mov_translated_a, mov_translated_b, mov_group_a, mov_group_b,
        toUInt8(1) as moved, toUInt8(0) as in_spine, toUInt8(0) as is_live, toUInt8(0) as is_out,
        toUInt8(0) as prev_live
    from pair_moves
    union all
    select
        consolidation_group, entity_a, account_a, entity_b, account_b, fiscal_year, fiscal_period,
        toUInt8(0),
        toFloat64(0), toFloat64(0), toFloat64(0), toFloat64(0), toFloat64(0), toFloat64(0),
        toUInt8(0), toUInt8(1), is_live, is_out, prev_live
    from spine_marked
),

per_period as (
    select
        consolidation_group, entity_a, account_a, entity_b, account_b, fiscal_year, fiscal_period,
        max(row_is_bs) as period_is_bs,
        sum(mov_local_a) as p_local_a,
        sum(mov_local_b) as p_local_b,
        sum(mov_translated_a) as p_translated_a,
        sum(mov_translated_b) as p_translated_b,
        sum(mov_group_a) as p_group_a,
        sum(mov_group_b) as p_group_b,
        max(moved) as has_move,
        max(in_spine) as has_spine,
        max(is_live) as live_flag,
        max(is_out) as out_flag,
        max(prev_live) as was_live
    from combined
    group by consolidation_group, entity_a, account_a, entity_b, account_b, fiscal_year, fiscal_period
),

{# the running totals a balance-sheet pair compares (decision 14), over every
   period either side booked, joined or not #}
to_date as (
    select
        *,
        max(period_is_bs) over (partition by {{ pair }}) as pair_is_bs,
        sum(p_local_a) over ({{ to_date }}) as cum_local_a,
        sum(p_local_b) over ({{ to_date }}) as cum_local_b,
        sum(p_translated_a) over ({{ to_date }}) as cum_translated_a,
        sum(p_translated_b) over ({{ to_date }}) as cum_translated_b,
        sum(p_group_a) over ({{ to_date }}) as cum_group_a,
        sum(p_group_b) over ({{ to_date }}) as cum_group_b
    from per_period
),

valued as (
    select
        consolidation_group,
        fiscal_year,
        fiscal_period,
        entity_a,
        account_a,
        entity_b,
        account_b,
        if(pair_is_bs = 1, 'balance', 'movement') as basis,
        multiIf(pair_is_bs = 0, '', out_flag = 1, 'left', was_live = 0, 'joined', '') as pair_event,
        multiIf(pair_is_bs = 0, p_local_a, out_flag = 1, toFloat64(0), cum_local_a) as local_a,
        multiIf(pair_is_bs = 0, p_local_b, out_flag = 1, toFloat64(0), cum_local_b) as local_b,
        multiIf(pair_is_bs = 0, p_translated_a, out_flag = 1, toFloat64(0), cum_translated_a) as translated_a,
        multiIf(pair_is_bs = 0, p_translated_b, out_flag = 1, toFloat64(0), cum_translated_b) as translated_b,
        multiIf(pair_is_bs = 0, p_group_a, out_flag = 1, toFloat64(0), cum_group_a) as group_a,
        multiIf(pair_is_bs = 0, p_group_b, out_flag = 1, toFloat64(0), cum_group_b) as group_b
    from to_date
    where has_spine = 1
      and (
          {# balance sheet: a period something moved, the first period together, and the first after a partner left #}
          (pair_is_bs = 1 and ((live_flag = 1 and (has_move = 1 or was_live = 0)) or (out_flag = 1 and was_live = 1)))
          {# P&L: a period something moved while both are in the group #}
          or (pair_is_bs = 0 and live_flag = 1 and has_move = 1)
      )
),

{# an entity's functional currency is one per entity #}
entity_currency as (
    select consolidation_group as currency_group, data_area_id as currency_entity,
           any(accounting_currency) as functional_currency
    from {{ ref('gold_consolidated_trial_balance') }}
    group by consolidation_group, data_area_id
),

group_settings as (
    select
        consolidation_group as settings_group,
        any({{ diff_account_expr }}) as diff_account,
        any({{ tolerance_expr }}) as diff_tolerance
    from {{ source('epm_gold', 'consolidation_groups') }}
    where data_area_id = ''
    group by consolidation_group
),

settled as (
    select
        v.consolidation_group as consolidation_group,
        v.fiscal_year as fiscal_year,
        v.fiscal_period as fiscal_period,
        v.entity_a as entity_a,
        v.account_a as account_a,
        v.entity_b as entity_b,
        v.account_b as account_b,
        v.basis as basis,
        v.pair_event as pair_event,
        ca.functional_currency as currency_a,
        cb.functional_currency as currency_b,
        v.local_a as local_a,
        v.local_b as local_b,
        v.translated_a as translated_a,
        v.translated_b as translated_b,
        v.group_a as group_a,
        v.group_b as group_b,
        {# join_use_nulls=0: a group with no settings row gets '' and 0 #}
        gs.diff_account as ic_difference_account,
        gs.diff_tolerance as tolerance
    from valued as v
    left join entity_currency as ca
        on ca.currency_group = v.consolidation_group and ca.currency_entity = v.entity_a
    left join entity_currency as cb
        on cb.currency_group = v.consolidation_group and cb.currency_entity = v.entity_b
    left join group_settings as gs
        on gs.settings_group = v.consolidation_group
)

select
    consolidation_group,
    fiscal_year,
    fiscal_period,
    entity_a,
    account_a,
    entity_b,
    account_b,
    basis,
    pair_event,
    currency_a,
    currency_b,
    local_a,
    local_b,
    {# decision 12: matched and compared at 100% #}
    translated_a as balance_a,
    translated_b as balance_b,
    group_a as group_balance_a,
    group_b as group_balance_b,
    {# the share of each side the group view holds (ownership) #}
    if(abs(translated_a) >= 0.005, group_a / translated_a, 1.0) as share_a,
    if(abs(translated_b) >= 0.005, group_b / translated_b, 1.0) as share_b,
    {# offsetting sides only: two debits (or two credits) match nothing #}
    if(translated_a * translated_b < 0, least(abs(translated_a), abs(translated_b)), 0) as matched_amount,
    translated_a + translated_b as difference,
    {# the previous model's name for the same figure #}
    translated_a + translated_b as net_balance,
    {# what is left of each side (100%) once the matched amount is eliminated #}
    translated_a - sign(translated_a) * matched_amount as residual_a,
    translated_b - sign(translated_b) * matched_amount as residual_b,
    multiIf(
        abs(translated_a + translated_b) < 0.005, 'none',
        currency_a != currency_b, 'fx',
        abs(local_a + local_b) >= 0.005, 'booking',
        'fx'
    ) as difference_cause,
    ic_difference_account,
    tolerance,
    multiIf(
        difference_cause = 'none', 'matched',
        difference_cause = 'fx', 'fx_difference',
        abs(translated_a + translated_b) <= tolerance, 'within_tolerance',
        'over_tolerance'
    ) as match_status
from settled
