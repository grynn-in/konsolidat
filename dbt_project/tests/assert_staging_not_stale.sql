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

    LAGGING — a table missing from the latest reconcile run. reconcile_all()
    stamps every watermark it writes with one run id; a write-through stamps
    none (''). Every table with a watermark row and no row from the latest
    run is one that run could not reach, including a table no reconcile has
    ever stamped: one that has failed in every reconcile since the upgrade
    keeps only its old '' stamp, and is exactly the case below. (Retired
    tables lose their rows in konsol's _retired_watermark_cleanup; on
    11 Oct 2026 every live table was in the 7 Oct reconcile, none is
    write-through only.) This is the case
    that matters most: epm_staging.ownership_periods held three rows dated
    2026-06-19 for records Frappe no longer had, and AMDE at 75% from that
    ghost row drove every consolidated statement while Frappe's own
    Consolidation Group said 100%.

    konsolidat#246, option #246-1 (Deepak Pai, 11 Oct 2026). LAGGING used to
    mean "more than lag_hours older than the newest watermark of any table".
    One write-through edit then made every untouched table look stale:
    publishing one Reporting Hierarchy gave 26 LAGGING rows for tables whose
    rows were current. A write-through neither joins nor leaves a run, so it
    can no longer do that. Rejected: #246-2 (drop LAGGING) and #246-3 (raise
    the lag hours).

    The latest run is the settled run that started last (its earliest
    stamp). A run is settled once its newest stamp is at least
    watermark_run_settle_seconds (default 60) old: a reconcile still running
    when dbt tests (a fresh install's queued reconcile_warehouse can overlap
    one) has stamped only the tables it has reached so far, and judging it
    would report the rest LAGGING for the second or so it takes to finish.
    Until it settles, the run before it is judged. A run that failed or was
    killed partway is the latest run once settled, so every table it did not
    reach is LAGGING, even one a write-through has refreshed since: the rule
    asks whether the reconcile reached the table, not whether the table is
    recent.

    NO_RECONCILE_RUN — no reconcile has stamped a run id yet. An upgrading
    site is in this state from the moment the watermark gains its
    reconcile_run_id column (konsol's ensure_reference_tables(), or
    sync_watermark_upgrade() in on-run-start) until the first reconcile after
    it, which konsol's migrate runs. That window must not go red, and must not
    pass for ever either: the test allows lag_hours from the column's arrival,
    read from system.tables.metadata_modification_time, then fails. Both
    writers issue that ALTER only when the column is missing, because an ALTER
    that changes nothing still moves that time.

    Deliberately NOT dbt's built-in source freshness. That keys on the data's
    own updated_at, so a table nobody edited reads as stale and an empty table
    reads as stale — on this project it marks most of epm_staging red, which is
    why nobody runs it. The watermark records when the *sync* ran, not when the
    data changed, so "unchanged" and "not syncing" stop looking alike.

    Tune the grace with --vars '{"watermark_lag_hours": N}'. It now bounds only
    NO_RECONCILE_RUN; LAGGING has no time threshold.

    Returns one row per problem — dbt fails the run when any row comes back.
#}

{% set lag_hours = var('watermark_lag_hours', 24) %}
{% set settle_seconds = var('watermark_run_settle_seconds', 60) %}
{% set wm = source('epm_staging', 'sync_watermark') %}

with stamps as (

    select table_name, synced_at, row_count, reconcile_run_id
    from {{ wm }}

),

watermark as (

    select
        table_name,
        argMax(row_count, synced_at) as expected_rows,
        max(synced_at)               as last_synced_at
    from stamps
    group by table_name

),

runs as (

    select
        reconcile_run_id as run_id,
        min(synced_at)   as run_started_at,
        max(synced_at)   as run_last_stamp_at
    from stamps
    where reconcile_run_id != ''
    group by reconcile_run_id

),

-- One row even with no run: an aggregate over nothing returns its defaults.
-- runs_seen counts every run (it ends NO_RECONCILE_RUN's grace); the latest
-- run is chosen among settled ones only.
latest_run as (

    select
        argMaxIf(run_id, run_started_at,
                 run_last_stamp_at <= now() - {{ settle_seconds }}) as latest_run_id,
        maxIf(run_started_at,
              run_last_stamp_at <= now() - {{ settle_seconds }})    as latest_started_at,
        countIf(run_last_stamp_at <= now() - {{ settle_seconds }})  as settled_runs,
        count()                                                    as runs_seen
    from runs

),

in_latest_run as (

    select distinct table_name
    from stamps
    where reconcile_run_id = (select latest_run_id from latest_run)

),

-- Every table with a watermark row; its last run, '' when no run ever
-- stamped it (argMaxIf over no rows returns the type default).
judged as (

    select
        table_name,
        argMaxIf(reconcile_run_id, synced_at, reconcile_run_id != '') as last_run_id,
        maxIf(synced_at, reconcile_run_id != '')                      as last_run_at
    from stamps
    group by table_name

),

actual as (

    select
        concat(database, '.', name) as table_name,
        total_rows
    from system.tables
    where database in ('epm_staging', 'epm_gold')

),

watermark_shape as (

    select metadata_modification_time as shaped_at
    from system.tables
    where database = '{{ wm.schema }}' and name = '{{ wm.identifier }}'

)

select
    w.table_name,
    w.expected_rows,
    coalesce(a.total_rows, 0) as actual_rows,
    w.last_synced_at,
    'EMPTIED: the sync wrote rows, the table has none' as problem
from watermark as w
left join actual as a on a.table_name = w.table_name
where w.expected_rows > 0
  and (a.table_name = '' or coalesce(a.total_rows, 0) = 0)

union all

select
    r.table_name,
    w.expected_rows,
    coalesce(a.total_rows, 0) as actual_rows,
    w.last_synced_at,
    concat(
        'LAGGING: missing from the latest reconcile run ', l.latest_run_id,
        ' (started ', toString(l.latest_started_at), '); ',
        if(r.last_run_id = '',
           'no reconcile run has ever stamped it',
           concat('last reconciled by run ', r.last_run_id, ' at ', toString(r.last_run_at))),
        ' — its rows may outlive their Frappe records'
    ) as problem
from judged as r
inner join watermark as w on w.table_name = r.table_name
left join actual as a on a.table_name = r.table_name
cross join latest_run as l
where l.settled_runs > 0
  and r.table_name not in (select table_name from in_latest_run)

union all

select
    '{{ wm.schema }}.{{ wm.identifier }}' as table_name,
    toUInt64(0) as expected_rows,
    toUInt64(0) as actual_rows,
    s.shaped_at as last_synced_at,
    concat(
        'NO_RECONCILE_RUN: no reconcile has stamped a run id in the ',
        toString(dateDiff('hour', s.shaped_at, now())),
        'h since the watermark gained reconcile_run_id (grace {{ lag_hours }}h)',
        ' — run bench execute konsol.clickhouse.reconcile_all'
    ) as problem
from latest_run as l
cross join watermark_shape as s
where l.runs_seen = 0
  and dateDiff('hour', s.shaped_at, now()) > {{ lag_hours }}
