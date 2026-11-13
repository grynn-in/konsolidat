-- STUB (red evidence): returns no rows.
select entry_name from {{ source('budget_raw', 'budget_entries') }} where 1 = 0
