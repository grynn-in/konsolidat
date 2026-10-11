{#
    konsolidat#246, option #246-1 (Deepak Pai, 11 Oct 2026): the sync watermark
    carries the id of the reconcile run that stamped each row, and
    assert_staging_not_stale reads it.

    konsol owns the table and upgrades it in ensure_reference_tables(). This is
    the same upgrade, for a stack where this project runs before konsol has: it
    keeps the test from reading a column that is not there, and it starts the
    test's no-run-yet grace at the upgrade, whoever made it.

    The ALTER is issued only when the column is missing. An ALTER that changes
    nothing still rewrites the table's metadata_modification_time (measured on
    ClickHouse 24.8), and the test measures its grace from that time, so
    issuing it on every dbt run would keep the grace open for ever.

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
        "select count() from system.columns where database = '" ~ wm.schema
        ~ "' and table = '" ~ wm.identifier ~ "' and name = 'reconcile_run_id'"
    ) -%}
    {%- if found.columns[0].values()[0] | int > 0 -%}
        {{ return('select 1') }}
    {%- endif -%}
    {{ return(
        "ALTER TABLE " ~ wm.schema ~ "." ~ wm.identifier
        ~ " ADD COLUMN IF NOT EXISTS reconcile_run_id String,"
        ~ " MODIFY ORDER BY (table_name, reconcile_run_id)"
    ) }}
{% endmacro %}
