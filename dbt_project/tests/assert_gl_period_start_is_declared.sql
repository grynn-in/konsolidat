{#
    konsolidat#171 step 2d (task 5d): a Trial Balance Submission row whose entity has no fiscal calendar of its
    own is dated from konsol's declared calendar (declared_periods().start_date), the same calendar every other
    period-dated reader uses. This catches the wrong-but-not-epoch date that
    assert_tb_submission_period_start_not_epoch cannot see: an April-March site's FY2026 P1 is 2025-04-01,
    and a calendar-month fallback said 2026-01-01.

    Mirrors the join in silver_gl_entries (entity_fiscal_calendars -> silver_fiscal_periods): a row is judged
    here only when that join finds no own-calendar period. A period the declared calendar does not list is not
    judged here (it has no date: the epoch test and assert_trial_balance_period_declared name it).
#}
select
    g.data_area_id,
    g.fiscal_year,
    g.fiscal_period,
    g.document_number,
    g.accounting_date,
    dp.start_date as declared_start_date
from {{ ref('silver_gl_entries') }} as g
inner join {{ declared_periods() }} as dp
    on dp.fiscal_year = toUInt16(g.fiscal_year)
    and dp.fiscal_period = toUInt16(g.fiscal_period)
left join {{ source('epm_gold', 'entity_fiscal_calendars') }} as efc
    on g.data_area_id = efc.data_area_id
left join {{ ref('silver_fiscal_periods') }} as sfp
    on sfp.calendar_id = coalesce(efc.fiscal_calendar_id, 'Fiscal')
    and {{ extract_year('sfp.year_start_date') }} = g.fiscal_year
    and sfp.calendar_month = g.fiscal_period
where g.posting_type = 'Trial Balance Submission'
  and sfp.period_start_date = toDate(0)
  and g.accounting_date != dp.start_date
