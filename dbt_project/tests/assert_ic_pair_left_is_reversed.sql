{#
    #175 third review M1: while a balance-sheet pair is not live in a group,
    nothing of it is eliminated there. Every elimination posted while both
    sides were in the group has been reversed.

    Membership is resolved here from the ownership data itself, not from
    gold_entity_ownership or the model's spine: an entity line-consolidates
    into a group at a date when EVERY link of its chain to that group
    (consolidation_ancestry) has an ownership period covering the date with
    method full or proportional. So a partner that was disposed of, a
    sub-group sold while its own entity's ownership stays open, and a stake
    moved to equity all count as having left, per group.

    For every balance-sheet pair, and every period the warehouse holds from
    the pair's first reconciliation row to the group's latest period, in
    which either side is not a member: the pair's eliminations to date, per
    view, account and entity, are 0. That covers the periods before a pair
    joins (nothing posted yet) and every period after it left (all reversed).
#}

with bs_pairs as (
    select consolidation_group, entity_a, account_a, entity_b, account_b,
           min(tuple(fiscal_year, fiscal_period)) as first_period
    from {{ ref('gold_ic_reconciliation') }}
    where basis = 'balance'
    group by consolidation_group, entity_a, account_a, entity_b, account_b
),

group_last as (
    select consolidation_group as last_group, max(tuple(fiscal_year, fiscal_period)) as last_period
    from {{ ref('gold_consolidated_trial_balance') }}
    group by consolidation_group
),

periods as (
    select distinct fiscal_year, fiscal_period,
           {{ build_date_from_year_period('fiscal_year', 'fiscal_period') }} as period_date
    from {{ ref('gold_trial_balance') }}
),

pair_entities as (
    select consolidation_group, entity_a as data_area_id from bs_pairs
    union distinct
    select consolidation_group, entity_b from bs_pairs
),

{# one row per link of each entity's chain to the group, and period: is the
   link covered by an ownership period that line-consolidates? join_use_nulls=0:
   a link with no ownership period comes back with 1970-01-01 dates and '' #}
link_cover as (
    select a.consolidation_group as consolidation_group, a.data_area_id as data_area_id,
           p.fiscal_year as fiscal_year, p.fiscal_period as fiscal_period,
           a.link_group as link_group, a.link_data_area_id as link_data_area_id,
           max(o.effective_date <= p.period_date and o.end_date >= p.period_date
               and o.consolidation_method in ('full', 'proportional')) as covered
    from {{ source('epm_staging', 'consolidation_ancestry') }} as a
    inner join pair_entities as pe
        on pe.consolidation_group = a.consolidation_group and pe.data_area_id = a.data_area_id
    cross join periods as p
    left join {{ source('epm_staging', 'ownership_periods') }} as o
        on o.consolidation_group = a.link_group and o.data_area_id = a.link_data_area_id
    group by a.consolidation_group, a.data_area_id, p.fiscal_year, p.fiscal_period,
             a.link_group, a.link_data_area_id
),

members as (
    select consolidation_group, data_area_id, fiscal_year, fiscal_period
    from link_cover
    group by consolidation_group, data_area_id, fiscal_year, fiscal_period
    having min(covered) = 1
),

not_live as (
    select bp.consolidation_group as consolidation_group, bp.entity_a as entity_a, bp.account_a as account_a,
           bp.entity_b as entity_b, bp.account_b as account_b,
           p.fiscal_year as fiscal_year, p.fiscal_period as fiscal_period
    from bs_pairs as bp
    inner join group_last as gl on gl.last_group = bp.consolidation_group
    cross join periods as p
    left join members as ma
        on ma.consolidation_group = bp.consolidation_group and ma.data_area_id = bp.entity_a
        and ma.fiscal_year = p.fiscal_year and ma.fiscal_period = p.fiscal_period
    left join members as mb
        on mb.consolidation_group = bp.consolidation_group and mb.data_area_id = bp.entity_b
        and mb.fiscal_year = p.fiscal_year and mb.fiscal_period = p.fiscal_period
    where tuple(p.fiscal_year, p.fiscal_period) >= bp.first_period
      and tuple(p.fiscal_year, p.fiscal_period) <= gl.last_period
      and (ma.data_area_id = '' or mb.data_area_id = '')
),

legs as (
    select consolidation_group, entity_a, account_a, entity_b, account_b, fiscal_year, fiscal_period,
           elimination_view, debit_account as account, debit_entity as entity, debit_elimination as amount
    from {{ ref('gold_ic_eliminations') }}
    where rule_type = 'balance' and basis = 'balance'
    union all
    select consolidation_group, entity_a, account_a, entity_b, account_b, fiscal_year, fiscal_period,
           elimination_view, credit_account, credit_entity, credit_elimination
    from {{ ref('gold_ic_eliminations') }}
    where rule_type = 'balance' and basis = 'balance'
)

select
    n.consolidation_group as consolidation_group,
    concat(n.entity_a, '/', n.account_a, ' <> ', n.entity_b, '/', n.account_b) as pair,
    n.fiscal_year as fiscal_year,
    n.fiscal_period as fiscal_period,
    l.elimination_view as elimination_view,
    l.account as account,
    l.entity as entity,
    sum(l.amount) as eliminated_to_date
from not_live as n
inner join legs as l
    on l.consolidation_group = n.consolidation_group
    and l.entity_a = n.entity_a and l.account_a = n.account_a
    and l.entity_b = n.entity_b and l.account_b = n.account_b
where tuple(l.fiscal_year, l.fiscal_period) <= tuple(n.fiscal_year, n.fiscal_period)
group by n.consolidation_group, n.entity_a, n.account_a, n.entity_b, n.account_b,
         n.fiscal_year, n.fiscal_period, l.elimination_view, l.account, l.entity
having abs(sum(l.amount)) >= 0.01
