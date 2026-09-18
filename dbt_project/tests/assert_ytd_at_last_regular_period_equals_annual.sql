{{
    config(
        severity='warn'
    )
}}
-- Test: per dimension, the YTD at a fiscal year's LAST REGULAR PERIOD equals the
-- sum of the year's Regular periods' activity.
--
-- Both sides come from the declared calendar (epm_staging.fiscal_periods, konsol's):
--   * "last Regular period" = the year's max fiscal_period with period_type = 'Regular'
--     (not a hardcoded 12: a calendar may declare 4, 12 or 52 Regular periods);
--   * "annual" leaves the year's Closing-type period(s) out. The Closing period is
--     where silver_tb_movements posts the year-end close of a period-end-balance
--     file (konsolidat#199): P&L balances to zero, their sum into retained earnings.
--     That close is a reclassification of the year's result, not activity, so a sum
--     over every period would read every P&L account's annual as 0 while the YTD at
--     the last Regular period still carries the year's result (10,643 rows on the
--     first live build with closes). A period the calendar does not know counts as
--     activity: nothing is invented, only declared Closing periods are excluded.
-- A fiscal year the calendar does not declare has no last Regular period and is not
-- judged here.
--
-- Warns (not fails) because some dimension combos have no posting at the last
-- Regular period, so their YTD stops at an earlier period.
with calendar as (
    select
        toUInt16(fiscal_year) as fiscal_year,
        toUInt16(fiscal_period) as fiscal_period,
        max(period_type = 'Closing') as is_closing
    from {{ source('epm_staging', 'fiscal_periods') }}
    group by fiscal_year, fiscal_period
),
last_regular as (
    select
        toUInt16(fiscal_year) as fiscal_year,
        toUInt16(max(fiscal_period)) as last_regular_period
    from {{ source('epm_staging', 'fiscal_periods') }}
    where period_type = 'Regular'
    group by fiscal_year
),
annual as (
    select
        data_area_id, fiscal_year, main_account,
        {{ dim_select(trailing=true) }}
        sum(period_net_amount) as annual_total
    from {{ ref('gold_trial_balance') }}
    where (toUInt16(fiscal_year), toUInt16(fiscal_period)) not in (
        select fiscal_year, fiscal_period from calendar where is_closing = 1
    )
    group by data_area_id, fiscal_year, main_account{{ dim_group_by(leading=true) }}
)
select
    ytd.data_area_id,
    ytd.fiscal_year,
    ytd.fiscal_period as last_regular_period,
    ytd.main_account,
    ytd.dim_cost_center,
    ytd.dim_department,
    ytd.dim_business_unit,
    ytd.ytd_net_amount as ytd_at_last_regular_period,
    annual.annual_total,
    abs(ytd.ytd_net_amount - annual.annual_total) as gap
from {{ ref('gold_ytd_trial_balance') }} as ytd
inner join last_regular as lr
    on lr.fiscal_year = toUInt16(ytd.fiscal_year)
    and lr.last_regular_period = toUInt16(ytd.fiscal_period)
inner join annual
    on ytd.data_area_id = annual.data_area_id
    and ytd.fiscal_year = annual.fiscal_year
    and ytd.main_account = annual.main_account
    and ytd.dim_cost_center = annual.dim_cost_center
    and ytd.dim_department = annual.dim_department
    and ytd.dim_business_unit = annual.dim_business_unit
where abs(ytd.ytd_net_amount - annual.annual_total) > 0.01
