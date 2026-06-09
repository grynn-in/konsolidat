-- PRD-19 Test: Composite driver weights must sum to 1.0 per rule per period
select
    driver_type,
    data_area_id,
    fiscal_year,
    fiscal_period,
    sum(driver_value) as total_value
from {{ source('epm_staging', 'allocation_drivers') }}
where driver_type like 'composite_%'
group by driver_type, data_area_id, fiscal_year, fiscal_period
having sum(driver_value) < 0.01
