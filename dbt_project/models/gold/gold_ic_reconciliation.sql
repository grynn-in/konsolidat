{{
    config(
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# Intercompany reconciliation: one row per PAIR, the two sides of one
   intercompany balance (konsolidat#148, konsol#159).

   A side is (entity, partner, account): an entity's balance on a flagged
   intercompany account with one partner, in group currency. Its other side
   is (partner, entity, counterpart), what the partner books against it. The
   pair is keyed with its lexically smaller side as `a`, so both sides land on
   one row whichever entity reports first.

   Decided 13 Sep 2026:
   - the counterparty is the partner on each row, never guessed (decision 1);
     a row with no partner is not paired here: gold_ic_unmatched lists it
     (decision 2);
   - a pair whose sides don't match eliminates the matched amount, the smaller
     of the two, and books the difference to the group's intercompany-
     difference account, shown against the group's tolerance (decision 4).
     gold_ic_eliminations turns this model into entries.

   Only pairs inside the group: the partner must itself consolidate line by
   line into the group in that period. A balance with an entity outside it (a
   sibling sub-group, an equity-method associate) is external at this level,
   neither eliminated nor unmatched. gold_consolidated_trial_balance already
   holds only line-consolidated entities, so the reporting side is inside.

   A side with no row is a balance of 0: a partner that booked nothing leaves
   the whole balance as the difference. #}

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

with ic_accounts as (
    {{ ic_account_map() }}
),

members as (
    select distinct consolidation_group, data_area_id, fiscal_year, fiscal_period
    from {{ ref('gold_entity_ownership') }}
    where has_complete_chain = 1
      and consolidation_method not in ('equity', 'none')
),

sides as (
    select
        ctb.consolidation_group as consolidation_group,
        ctb.fiscal_year as fiscal_year,
        ctb.fiscal_period as fiscal_period,
        ctb.data_area_id as entity,
        ctb.partner_data_area_id as partner,
        ctb.main_account as account,
        ica.counterpart as counterpart,
        sum(ctb.group_amount) as balance
    from {{ ref('gold_consolidated_trial_balance') }} as ctb
    inner join ic_accounts as ica
        on ctb.main_account = ica.account
    where ctb.partner_data_area_id != ''
      and ctb.partner_data_area_id != ctb.data_area_id
      and (ctb.consolidation_group, ctb.partner_data_area_id, ctb.fiscal_year, ctb.fiscal_period) in (
          select consolidation_group, data_area_id, fiscal_year, fiscal_period from members
      )
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
        balance,
        tuple(entity, account) < tuple(partner, counterpart) as is_a,
        if(is_a, entity, partner) as entity_a,
        if(is_a, account, counterpart) as account_a,
        if(is_a, partner, entity) as entity_b,
        if(is_a, counterpart, account) as account_b
    from sides
),

pairs as (
    select
        consolidation_group,
        fiscal_year,
        fiscal_period,
        entity_a,
        account_a,
        entity_b,
        account_b,
        sumIf(balance, is_a) as balance_a,
        sumIf(balance, not is_a) as balance_b
    from keyed
    group by consolidation_group, fiscal_year, fiscal_period, entity_a, account_a, entity_b, account_b
),

group_settings as (
    select
        consolidation_group as settings_group,
        any({{ diff_account_expr }}) as diff_account,
        any({{ tolerance_expr }}) as diff_tolerance
    from {{ source('epm_gold', 'consolidation_groups') }}
    where data_area_id = ''
    group by consolidation_group
)

select
    p.consolidation_group as consolidation_group,
    p.fiscal_year as fiscal_year,
    p.fiscal_period as fiscal_period,
    p.entity_a as entity_a,
    p.account_a as account_a,
    p.entity_b as entity_b,
    p.account_b as account_b,
    p.balance_a as balance_a,
    p.balance_b as balance_b,
    {# offsetting sides only: two debits (or two credits) match nothing #}
    if(p.balance_a * p.balance_b < 0, least(abs(p.balance_a), abs(p.balance_b)), 0) as matched_amount,
    p.balance_a + p.balance_b as difference,
    {# the previous model's name for the same figure #}
    p.balance_a + p.balance_b as net_balance,
    {# join_use_nulls=0: a group with no settings row gets '' and 0 #}
    gs.diff_account as ic_difference_account,
    gs.diff_tolerance as tolerance,
    multiIf(
        abs(p.balance_a + p.balance_b) < 0.005, 'matched',
        abs(p.balance_a + p.balance_b) <= gs.diff_tolerance, 'within_tolerance',
        'over_tolerance'
    ) as match_status
from pairs as p
left join group_settings as gs
    on p.consolidation_group = gs.settings_group
