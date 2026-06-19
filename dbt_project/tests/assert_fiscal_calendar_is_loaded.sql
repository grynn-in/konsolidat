-- #77 — Guard against the silent fiscal-calendar fallback (FY0/P0 regression).
--
-- silver_gl_entries joins each GL row to a fiscal calendar; when the join misses,
-- ClickHouse fills fp.* with 0 and the model falls back to deriving the period
-- from the posting date (see #65). That fallback is correct for calendar fiscal
-- years but silently wrong for offset ones — and a missed join is exactly what
-- put every row in FY0/P0 before #65/#76.
--
-- This test fails if any entity that actually has GL activity points (via
-- entity_fiscal_calendars) at a fiscal calendar that ISN'T loaded in
-- silver_fiscal_periods. That is the precise condition under which the join
-- silently misses, turning a future re-break (e.g. a seed pointing an active
-- entity back at a non-existent calendar, or a calendar dropping out of the
-- raw load) into a failing test instead of quietly-wrong numbers.
select distinct
    efc.data_area_id,
    efc.fiscal_calendar_id
from {{ ref('entity_fiscal_calendars') }} as efc
where efc.data_area_id in (
        select distinct data_area_id from {{ ref('silver_gl_entries') }}
    )
  and efc.fiscal_calendar_id not in (
        select distinct calendar_id from {{ ref('silver_fiscal_periods') }}
    )
