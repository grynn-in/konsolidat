{#
    Fails when a write-through table no longer holds what its last successful
    sync claimed to have written.

    Background: D11 wanted ClickHouse to read Frappe's MariaDB directly so
    metadata could never go stale. F4 reversed that — write-through avoids
    making every dbt run a live dependency on the Frappe database and avoids
    needing ClickHouse to reach MariaDB across a customer's network. The cost
    of reversing it is losing D11's one real benefit, "never stale". This test
    is how that benefit comes back without the coupling.

    konsol's clickhouse.sync_table() stamps epm_staging.sync_watermark on every
    successful sync: which table, when, and how many rows it wrote. Anything
    that empties or truncates one of those tables afterwards — a wiped
    ClickHouse, a restore in the wrong order, a half-finished migration — shows
    up here as the watermark promising rows the table no longer has.

    This matters more now that gold_consolidation_hierarchy no longer falls back
    to the consolidation_groups seed. Previously an empty
    epm_staging.consolidation_hierarchy silently swapped in stale CSV ownership
    percentages; now it produces nothing, and this test names why.

    Returns one row per problem — dbt fails the run when any row comes back.
#}

with watermark as (

    select
        table_name,
        argMax(row_count, synced_at) as expected_rows,
        max(synced_at)               as last_synced_at
    from {{ source('epm_staging', 'sync_watermark') }}
    group by table_name

),

actual as (

    select
        concat(database, '.', name) as table_name,
        total_rows
    from system.tables
    where database in ('epm_staging', 'epm_gold')

)

select
    w.table_name,
    w.expected_rows,
    coalesce(a.total_rows, 0) as actual_rows,
    w.last_synced_at,
    if(a.table_name = '', 'table no longer exists', 'table is empty but the sync wrote rows') as problem
from watermark as w
left join actual as a on a.table_name = w.table_name
where w.expected_rows > 0
  and (a.table_name = '' or coalesce(a.total_rows, 0) = 0)
