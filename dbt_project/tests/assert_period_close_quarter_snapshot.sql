{#
    A quarter end is read, not closed: check (c) of the period-close family (konsolidat#397).
    Proposed on that issue; no decision is recorded yet.

    Nothing stores a quarter close. A quarter's P&L is the sum of its Regular periods' movements and
    the quarter-end position is the YTD at the quarter's last Regular period; both are derived from
    the period movements every time, so the stored balances never change at a quarter end. The
    quarter a period falls in is the one konsol's fiscal calendar declares
    (epm_staging.fiscal_periods.quarter), not a hardcoded 3/6/9/12. Two rules, P&L accounts only
    (is_pnl = 1), per (entity, fiscal year, quarter, account, <the declared dimensions>):

      quarter_total_differs_from_calendar  gold_pnl_quarterly.quarter_net_amount differs from the sum
                                           of gold_trial_balance.period_net_amount over the Regular
                                           periods the calendar declares in that quarter.
                                           gold_pnl_quarterly maps periods to quarters through
                                           gold_period_hierarchy (the fiscal_quarter_mapping and
                                           fiscal_extra_periods vars), so this is where a var that
                                           disagrees with the calendar shows: a Closing period
                                           counted in Q4 (the year-end close would empty Q4's P&L),
                                           a calendar with a 13th Regular period, a quarter mapped
                                           to other periods.
      quarter_end_ytd_differs              gold_ytd_trial_balance.ytd_net_amount at the quarter's
                                           last declared Regular period differs from the sum of the
                                           year's Regular-period movements up to that period. The
                                           YTD window runs over every period, so a movement in a
                                           non-Regular period before the quarter end (P&L in an
                                           Opening period) would leak into the quarter-end
                                           snapshot. Judged where the YTD has a row at the quarter
                                           end; a key with no row there is read from its last row.

    A calendar quarter label is judged only on Regular periods that carry one (quarter != '').
    The Closing, Opening and Adjustment periods' own labels (konsol labels P13 'Q4') are not read:
    those periods are never part of a quarter's activity. gold_pnl_quarterly rows under a label
    the calendar never declares for a Regular period of that year ('CLS', 'OPN') are not judged.
    Year-end equivalent: assert_ytd_at_last_regular_period_equals_annual (warn), which this
    generalises to every quarter end, on P&L, at error.

    Tolerance 0.01.
    Fixtures: test_fixtures/assert_period_close_quarter_snapshot.*.sql
#}

{{ config(severity='error') }}

with regular_periods as (
    select
        toUInt16(fiscal_year) as fiscal_year,
        toUInt16(fiscal_period) as fiscal_period,
        any(quarter) as fiscal_quarter
    from {{ source('epm_staging', 'fiscal_periods') }}
    where period_type = 'Regular'
      and quarter != ''
    group by fiscal_year, fiscal_period
),

quarter_ends as (
    select fiscal_year, fiscal_quarter, max(fiscal_period) as quarter_end_period
    from regular_periods
    group by fiscal_year, fiscal_quarter
),

quarter_legs as (
    select
        tb.data_area_id as data_area_id,
        toUInt16(tb.fiscal_year) as fiscal_year,
        rp.fiscal_quarter as fiscal_quarter,
        tb.main_account as main_account,
        {{ dim_select(prefix='tb.', trailing=true) }}
        toDecimal128(tb.period_net_amount, {{ amount_scale() }}) as amount
    from {{ ref('gold_trial_balance') }} as tb
    inner join regular_periods as rp
        on rp.fiscal_year = toUInt16(tb.fiscal_year)
        and rp.fiscal_period = toUInt16(tb.fiscal_period)
    where tb.is_pnl = 1

    union all

    select
        q.data_area_id as data_area_id,
        toUInt16(q.fiscal_year) as fiscal_year,
        q.fiscal_quarter as fiscal_quarter,
        q.main_account as main_account,
        {{ dim_select(prefix='q.', trailing=true) }}
        toDecimal128(-q.quarter_net_amount, {{ amount_scale() }}) as amount
    from {{ ref('gold_pnl_quarterly') }} as q
    where (toUInt16(q.fiscal_year), q.fiscal_quarter) in (select fiscal_year, fiscal_quarter from quarter_ends)
),

quarter_total_differs_from_calendar as (
    select
        data_area_id, fiscal_year, fiscal_quarter, main_account,
        {{ dim_select(trailing=true) }}
        sum(amount) as difference,
        'quarter_total_differs_from_calendar' as reason
    from quarter_legs
    group by data_area_id, fiscal_year, fiscal_quarter, main_account{{ dim_group_by(leading=true) }}
    having abs(sum(amount)) > 0.01
),

ytd_at_quarter_end as (
    select
        y.data_area_id as data_area_id,
        toUInt16(y.fiscal_year) as fiscal_year,
        qe.fiscal_quarter as fiscal_quarter,
        qe.quarter_end_period as quarter_end_period,
        y.main_account as main_account,
        {{ dim_select(prefix='y.', trailing=true) }}
        toDecimal128(y.ytd_net_amount, {{ amount_scale() }}) as ytd_amount
    from {{ ref('gold_ytd_trial_balance') }} as y
    inner join quarter_ends as qe
        on qe.fiscal_year = toUInt16(y.fiscal_year)
        and qe.quarter_end_period = toUInt16(y.fiscal_period)
    where y.is_pnl = 1
),

regular_to_quarter_end as (
    select
        tb.data_area_id as data_area_id,
        qe.fiscal_year as fiscal_year,
        qe.fiscal_quarter as fiscal_quarter,
        tb.main_account as main_account,
        {{ dim_select(prefix='tb.', trailing=true) }}
        toDecimal128(sum(tb.period_net_amount), {{ amount_scale() }}) as regular_amount
    from {{ ref('gold_trial_balance') }} as tb
    inner join regular_periods as rp
        on rp.fiscal_year = toUInt16(tb.fiscal_year)
        and rp.fiscal_period = toUInt16(tb.fiscal_period)
    inner join quarter_ends as qe
        on qe.fiscal_year = rp.fiscal_year
    where tb.is_pnl = 1
      and rp.fiscal_period <= qe.quarter_end_period
    group by tb.data_area_id, qe.fiscal_year, qe.fiscal_quarter, tb.main_account{{ dim_group_by(prefix='tb.', leading=true) }}
),

quarter_end_ytd_differs as (
    select
        y.data_area_id as data_area_id,
        y.fiscal_year as fiscal_year,
        y.fiscal_quarter as fiscal_quarter,
        y.main_account as main_account,
        {{ dim_select(prefix='y.', trailing=true) }}
        y.ytd_amount - r.regular_amount as difference,
        'quarter_end_ytd_differs' as reason
    from ytd_at_quarter_end as y
    left join regular_to_quarter_end as r
        on r.data_area_id = y.data_area_id
        and r.fiscal_year = y.fiscal_year
        and r.fiscal_quarter = y.fiscal_quarter
        and r.main_account = y.main_account
        {{ dim_join_on('r', 'y') }}
    where abs(y.ytd_amount - r.regular_amount) > 0.01
)

select * from quarter_total_differs_from_calendar
union all
select * from quarter_end_ytd_differs
