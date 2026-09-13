{#
    #175 re-review M1: once a partner's ownership has ended, a balance-sheet
    pair's eliminations are reversed.

    A pair that was in the group (it has reconciliation rows up to the end)
    whose partner's ownership then ended (every ownership period of it ended),
    while the other side is still in the group after that date, must have a
    'left' row. There its values are 0, so the pair's eliminations to date
    are reversed (assert_ic_elimination_nets_zero and
    assert_ic_full_view_nets_zero check the amounts at that row). Without it
    the eliminations posted while the partner was in the group stayed in the
    from-inception balance sheet forever.
#}

with ownership_ends as (
    select data_area_id as ended_entity, max(end_date) as last_end
    from {{ source('epm_staging', 'ownership_periods') }}
    group by data_area_id
    having max(end_date) < toDate('2149-01-01')
),

members as (
    select distinct consolidation_group, data_area_id, fiscal_year, fiscal_period,
           {{ build_date_from_year_period('fiscal_year', 'fiscal_period') }} as period_date
    from {{ ref('gold_entity_ownership') }}
    where has_complete_chain = 1
      and consolidation_method not in ('equity', 'none')
),

bs_pairs as (
    select consolidation_group, entity_a, account_a, entity_b, account_b,
           min({{ build_date_from_year_period('fiscal_year', 'fiscal_period') }}) as first_row_date,
           countIf(pair_event = 'left') as left_rows
    from {{ ref('gold_ic_reconciliation') }}
    where basis = 'balance'
    group by consolidation_group, entity_a, account_a, entity_b, account_b
),

{# a side whose ownership ended, and the other side still in the group after it #}
should_leave as (
    select p.consolidation_group as consolidation_group, p.entity_a as entity_a, p.account_a as account_a,
           p.entity_b as entity_b, p.account_b as account_b, e.ended_entity as ended_entity,
           e.last_end as last_end, p.left_rows as left_rows
    from bs_pairs as p
    inner join ownership_ends as e on e.ended_entity = p.entity_b
    inner join members as m
        on m.consolidation_group = p.consolidation_group and m.data_area_id = p.entity_a
    where m.period_date > e.last_end and p.first_row_date <= e.last_end
    union all
    select p.consolidation_group, p.entity_a, p.account_a, p.entity_b, p.account_b, e.ended_entity,
           e.last_end, p.left_rows
    from bs_pairs as p
    inner join ownership_ends as e on e.ended_entity = p.entity_a
    inner join members as m
        on m.consolidation_group = p.consolidation_group and m.data_area_id = p.entity_b
    where m.period_date > e.last_end and p.first_row_date <= e.last_end
)

select distinct
    consolidation_group,
    concat(entity_a, '/', account_a, ' <> ', entity_b, '/', account_b) as detail,
    ended_entity,
    last_end
from should_leave
where left_rows = 0
