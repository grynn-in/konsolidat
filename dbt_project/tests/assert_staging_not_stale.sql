{#
    Fails when a write-through table's contents no longer match what its last
    successful sync says about it.

    Background: D11 wanted ClickHouse to read Frappe's MariaDB directly so
    metadata could never go stale. F4 reversed that — write-through avoids
    making every dbt run a live dependency on the Frappe database. The cost of
    reversing it is losing D11's one real benefit, "never stale". This is how
    that comes back without the coupling.

    konsol's clickhouse.sync_table() stamps epm_staging.sync_watermark on every
    successful sync, and reconcile_all() re-stamps every table after migrate.
    Two things can then be detected:

    EMPTIED — the watermark promises rows the table no longer has. A wiped
    ClickHouse, a restore in the wrong order, a half-finished migration.

    LAGGING — one table's watermark is far older than the newest. Because
    reconcile stamps them all together, a straggler means the reconcile could
    not reach that doctype while the others synced fine. This is the case that
    matters most: epm_staging.ownership_periods held three rows dated
    2026-06-19 for records Frappe no longer had, and AMDE at 75% from that
    ghost row drove every consolidated statement while Frappe's own
    Consolidation Group said 100%.

    Deliberately NOT dbt's built-in source freshness. That keys on the data's
    own updated_at, so a table nobody edited reads as stale and an empty table
    reads as stale — on this project it marks most of epm_staging red, which is
    why nobody runs it. The watermark records when the *sync* ran, not when the
    data changed, so "unchanged" and "not syncing" stop looking alike.

    Tune the lag with --vars '{"watermark_lag_hours": N}'.

    Returns one row per problem — dbt fails the run when any row comes back.
#}

{% set lag_hours = var('watermark_lag_hours', 24) %}

with watermark as (

    select
        table_name,
        argMax(row_count, synced_at) as expected_rows,
        max(synced_at)               as last_synced_at
    from {{ source('epm_staging', 'sync_watermark') }}
    group by table_name

),

newest as (

    select max(last_synced_at) as newest_sync from watermark

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
    'EMPTIED: the sync wrote rows, the table has none' as problem
from watermark as w
left join actual as a on a.table_name = w.table_name
cross join newest as n
where w.expected_rows > 0
  and (a.table_name = '' or coalesce(a.total_rows, 0) = 0)

union all

select
    w.table_name,
    w.expected_rows,
    coalesce(a.total_rows, 0) as actual_rows,
    w.last_synced_at,
    concat(
        'LAGGING: last synced ',
        toString(dateDiff('hour', w.last_synced_at, n.newest_sync)),
        'h before the newest sync — its rows may outlive their Frappe records'
    ) as problem
from watermark as w
left join actual as a on a.table_name = w.table_name
cross join newest as n
where dateDiff('hour', w.last_synced_at, n.newest_sync) > {{ lag_hours }}
