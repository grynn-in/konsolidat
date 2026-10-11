{#
    konsolidat#246, option #246-1 (Deepak Pai, 11 Oct 2026): the sync watermark
    carries the id of the reconcile run that stamped each row, and
    assert_staging_not_stale reads it.

    konsol owns the table and upgrades it in ensure_reference_tables(). This is
    the same upgrade, for a stack where this project runs before konsol has: it
    keeps the test from reading a column that is not there, and it starts the
    test's no-run-yet grace at the upgrade, whoever made it.

    The ALTER is issued only when the table's sorting key lacks the column,
    the same question konsol's _watermark_upgrade_ddl() asks of
    system.tables.sorting_key. An ALTER that changes nothing still rewrites
    the table's metadata_modification_time (measured on ClickHouse 24.8), and
    the test measures its grace from that time, so issuing it on every dbt run
    would keep the grace open for ever. A table that has the column but not
    the key (only a manual ALTER makes one) gets the ALTER too, and ClickHouse
    refuses it ("Existing column reconcile_run_id is used in the expression
    that was added to the sorting key"): the run fails loudly, as konsol's
    upgrade logs it, rather than judging runs on a table whose merges drop
    them. A missing table is left to the CREATE before this hook.

    One ALTER, no DEFAULT: ClickHouse adds a column to the sorting key only in
    the ALTER that adds it, and only when it has no default expression. Keep
    the statement identical to konsol's _WATERMARK_UPGRADE
    (tests/test_sync_watermark_ddl.py pins both texts).
#}
{% macro sync_watermark_upgrade() %}
    {%- set wm = source('epm_staging', 'sync_watermark') -%}
    {%- if not execute -%}
        {{ return('select 1') }}
    {%- endif -%}
    {%- set found = run_query(
        "select sorting_key from system.tables where database = '" ~ wm.schema
        ~ "' and name = '" ~ wm.identifier ~ "'"
    ) -%}
    {%- set keys = found.columns[0].values() -%}
    {%- if keys | length == 0 or 'reconcile_run_id' in keys[0] -%}
        {{ return('select 1') }}
    {%- endif -%}
    {{ return(
        "ALTER TABLE " ~ wm.schema ~ "." ~ wm.identifier
        ~ " ADD COLUMN IF NOT EXISTS reconcile_run_id String,"
        ~ " MODIFY ORDER BY (table_name, reconcile_run_id)"
    ) }}
{% endmacro %}
