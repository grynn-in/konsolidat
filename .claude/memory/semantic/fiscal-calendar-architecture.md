# Fiscal Calendar Architecture — 2026-06-08

## D365 OData Entities
- `FiscalCalendars` → bronze_fiscal_calendars: Calendar DEFINITIONS only (1 row per calendar, e.g. Fiscal: 2014-01-01 to 2028-12-31). NOT periods.
- `FiscalCalendarYears` → bronze_fiscal_calendar_years: Year ranges per calendar (e.g. Fiscal/2015: 2015-01-01 to 2015-12-31). 15 rows for Fiscal.
- `FiscalCalendarPeriods`: NOT extracted. Would have monthly periods per calendar. We generate them instead.

## silver_fiscal_periods
Generates 12 monthly periods per fiscal year from bronze_fiscal_calendar_years using `addMonths(start, 0..11)`. Covers standard and non-standard calendars (India Apr-Mar, Thailand Oct-Sep, etc.).

## Entity → Calendar Mapping
Seed: `dbt_project/seeds/entity_fiscal_calendars.csv` (65 entities)
Default fallback: 'Fiscal' via `coalesce(efc.fiscal_calendar_id, 'Fiscal')`
Key non-standard: CNMF→Fiscal_CN, INMF/DAIN→Fisscal_IN (typo is real), MYMF→Fiscal_MY, THMF/THPM→Fiscal_TH, SAMF→Fiscal_SA

## Gotcha
Do NOT use bronze_fiscal_calendars for period expansion — it's 1 row spanning 15 years.
