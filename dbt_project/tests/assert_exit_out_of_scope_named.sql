{{ config(severity='warn') }}
{#
    konsolidat#335, option A (decided 14 Nov 2026 by Deepak Pai), task X8. Design: .claude/memory/active/tasks-p1-round2.md,
    T8 (konsol repo): "named by a WARN, not posted".

    gold_ownership_exit_journal derecognises a bare link end (assert_exit_derecognises_carried). It deliberately does
    NOT post for the cases below. They are REPORTED here, one row per (group, entity, period, case), and never
    posted; a partial disposal or a retained interest is konsol#310.

      (a) step to equity: full or proportional in the previous declared period, equity now. The link continues, so
          the entity is still live and is no exit; its line-consolidated balances are not derecognised.
      (b) share drop through one path while another path still holds the entity: live in both periods, so not an
          exit; the effective share fell.
      (c) a layer-1 row (gold_consolidated_trial_balance) for an exited entity in or after its exit period, in a
          period where it is not live: a stale incremental slice (#154) after a back-dated end_date, or a trial
          balance uploaded after the exit. The balances were derecognised in the exit period and this row would
          carry them again.
      (d) topside (gold_consolidation_adjustments) on an exited entity: the exit does not reverse topside, so any
          cumulative topside balance up to the exit period stays in the group.

    Columns: consolidation_group, data_area_id, fiscal_year, fiscal_period, case_name, detail.
    Fixtures: test_fixtures/assert_exit_out_of_scope_named.*.must_flag.sql; .full_70pct passes (no WARN rows).
#}
with os_entities as (
    select distinct data_area_id
    from {{ source('epm_staging', 'consolidation_ancestry') }}
    where consolidation_group != '' and data_area_id != ''
),

os_entity_periods as (
    select
        e.data_area_id as data_area_id,
        dp.fiscal_year as fiscal_year,
        dp.fiscal_period as fiscal_period,
        dp.window_start_date as period_start_date,
        dp.window_end_date as period_date
    from os_entities as e
    cross join {{ declared_periods() }} as dp
),

{{ ownership_resolution_ctes('os_entity_periods', 'os_') }},

os_state as (
    select
        consolidation_group, data_area_id,
        toUInt16(fiscal_year) as fiscal_year, toUInt16(fiscal_period) as fiscal_period,
        toUInt8(has_complete_chain = 1 and consolidation_method in ('full', 'proportional', 'equity')) as is_live,
        consolidation_method, effective_ownership_pct, path_count
    from os_resolution
),

os_marked as (
    select
        *,
        lagInFrame(is_live, 1, toUInt8(0)) over w as prev_live,
        lagInFrame(consolidation_method, 1, '') over w as prev_method,
        lagInFrame(effective_ownership_pct, 1, toFloat64(0)) over w as prev_pct
    from os_state
    window w as (
        partition by consolidation_group, data_area_id
        order by fiscal_year, fiscal_period
        rows between unbounded preceding and current row
    )
),

exits as (
    select consolidation_group, data_area_id, toUInt16(fiscal_year) as fiscal_year,
        toUInt16(fiscal_period) as fiscal_period
    {#- the events of ownership_exits(), materialised once (#335, X23): every fixture of this test builds it #}
    from {{ ref('gold_ownership_exits') }}
),

case_a as (
    select consolidation_group, data_area_id, fiscal_year, fiscal_period,
        'step to equity' as case_name,
        concat('method ', prev_method, ' -> equity; the link continues, so the entity is not exited and its ',
               'line-consolidated balances are not derecognised (konsol#310)') as detail
    from os_marked
    where is_live = 1 and prev_live = 1 and prev_method in ('full', 'proportional') and consolidation_method = 'equity'
),

case_b as (
    select consolidation_group, data_area_id, fiscal_year, fiscal_period,
        'share drop through one path' as case_name,
        concat('effective share ', toString(round(prev_pct * 100, 4)), '% -> ',
               toString(round(effective_ownership_pct * 100, 4)), '% with ', toString(path_count),
               ' paths: another path still holds the entity, so it is live and not an exit (konsol#310)') as detail
    from os_marked
    where is_live = 1 and prev_live = 1 and path_count > 1 and effective_ownership_pct < prev_pct - 0.000001
),

layer1 as (
    select consolidation_group, data_area_id, toUInt16(fiscal_year) as fiscal_year,
        toUInt16(fiscal_period) as fiscal_period,
        sum(abs(toFloat64(local_amount))) as abs_amount, count() as n_rows
    from {{ ref('gold_consolidated_trial_balance') }}
    where data_area_id != ''
    group by consolidation_group, data_area_id, fiscal_year, fiscal_period
),

case_c as (
    select l.consolidation_group as consolidation_group, l.data_area_id as data_area_id,
        l.fiscal_year as fiscal_year, l.fiscal_period as fiscal_period,
        'layer-1 row after exit' as case_name,
        concat(toString(l.n_rows), ' layer-1 rows (', toString(round(l.abs_amount, 2)),
               ' absolute) in a period where the entity is not live, exited in FY', toString(x.fiscal_year), ' P',
               toString(x.fiscal_period), ': the exit derecognised its balances and these would be carried again') as detail
    from layer1 as l
    inner join exits as x
        on x.consolidation_group = l.consolidation_group and x.data_area_id = l.data_area_id
    inner join os_state as s
        on s.consolidation_group = l.consolidation_group and s.data_area_id = l.data_area_id
        and s.fiscal_year = l.fiscal_year and s.fiscal_period = l.fiscal_period
    where (l.fiscal_year, l.fiscal_period) >= (x.fiscal_year, x.fiscal_period)
      and s.is_live = 0 and l.abs_amount > {{ materiality_floor() }}
),

topside_balances as (
    select x.consolidation_group as consolidation_group, x.data_area_id as data_area_id,
        x.fiscal_year as fiscal_year, x.fiscal_period as fiscal_period, t.main_account as main_account,
        sum({{ cast_to_float64('t.net_amount') }}) as cumulative_net
    from exits as x
    inner join {{ ref('gold_consolidation_adjustments') }} as t
        on t.consolidation_group = x.consolidation_group and t.data_area_id = x.data_area_id
    where (toUInt16(t.fiscal_year), toUInt16(t.fiscal_period)) <= (x.fiscal_year, x.fiscal_period)
    group by x.consolidation_group, x.data_area_id, x.fiscal_year, x.fiscal_period, t.main_account
),

case_d as (
    select consolidation_group, data_area_id, fiscal_year, fiscal_period,
        'topside on exited entity' as case_name,
        concat(toString(count()), ' accounts carry a topside balance (', toString(round(sum(abs(cumulative_net)), 2)),
               ' absolute) up to the exit; the exit does not reverse topside') as detail
    from topside_balances
    where abs(cumulative_net) > {{ materiality_floor() }}
    group by consolidation_group, data_area_id, fiscal_year, fiscal_period
)

select * from case_a
union all
select * from case_b
union all
select consolidation_group, data_area_id, fiscal_year, fiscal_period, case_name, detail from case_c
union all
select * from case_d
