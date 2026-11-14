-- konsol#348 S2 (Q13-a): every budget row declares its layer and currency; a blank is never defaulted
-- (no silent fallback). Flags each row of epm_raw.budget_entries and epm_gold.budget_annual_input
-- whose layer or currency is ''.
-- Error severity: a blank layer would form its own silent slice and a blank currency is unconvertible.
{{ config(severity='error') }}

select
    'budget_entries' as source_table,
    entry_name as row_ref,
    scenario_id,
    data_area_id,
    fiscal_year,
    main_account,
    layer,
    currency
from {{ source('budget_raw', 'budget_entries') }}
where layer = '' or currency = ''

union all

select
    'budget_annual_input' as source_table,
    '' as row_ref,
    scenario_id,
    data_area_id,
    fiscal_year,
    main_account,
    layer,
    currency
from {{ source('epm_gold', 'budget_annual_input') }}
where layer = '' or currency = ''
