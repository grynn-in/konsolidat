{#
  cluster.sql — ClickHouse cluster-sharding support (opt-in, default OFF)

  Activation
  ----------
  Set `cluster_enabled: true` in dbt vars AND use the `cluster` profile target:

    dbt build --target cluster --vars '{"cluster_enabled": true}'

  or export `DBT_TARGET=cluster` and `DBT_CLUSTER_ENABLED=true` and rely on
  the profiles.yml defaults.

  Single-node default
  -------------------
  When `var('cluster_enabled', false)` is false (the default), every macro in
  this file returns exactly the same value as the original literal it replaces.
  The compiled SQL for single-node mode is therefore byte-for-byte identical to
  what existed before these macros were introduced.

  Opt-in pattern for a model
  --------------------------
  Replace the hardcoded engine / cluster config literals with macro calls:

    {{ config(
        engine    = cluster_engine('ReplacingMergeTree(_airbyte_extracted_at)'),
        order_by  = '(data_area_id, accounting_date, recid)',
        partition_by = 'toYear(accounting_date)',
        cluster   = cluster_name()
    ) }}

  The SELECT query body is never changed.

  Distributed overlay
  -------------------
  After `dbt build --target cluster --vars '{"cluster_enabled": true}'`
  completes, run the operation that creates Distributed tables on top of the
  ReplicatedMergeTree locals:

    dbt run-operation create_distributed_tables

  Architecture
  ------------
  Tables written by dbt models:
    epm_bronze.<model>_local   ReplicatedMergeTree  — one per shard (data)
  Distributed overlay (created by run-operation):
    epm_bronze.<model>         Distributed          — query surface for API/Cube.js

  Shard key: cityHash64(data_area_id) — a given legal entity colocates on one
  shard. NOTE: the shard column is `data_area_id` (the LE column materialized
  across bronze/silver/gold). The canonical `entity_id` is renamed to
  `data_area_id` at the bronze source boundary and is NOT present in epm_* tables.
  Partition keys are unchanged (sharding ⊥ partitioning).
  ClickHouse Keeper is used for coordination (replaces ZooKeeper).

  Open questions (NOT verified on this single-node build — needs a real cluster):
  - Hot-shard risk: a very large LE under cityHash64(data_area_id); consider
    composite key (data_area_id, fiscal_year) for largest tenants.
  - Rebalancing: accept skew on new-LE onboarding or run periodic reshard?
  - Cross-shard correctness of gold aggregation models (gold_trial_balance,
    gold_consolidated_trial_balance, IC eliminations, NCI).
  - All 144 dbt tests green in cluster mode.
#}

{# ─────────────────────────────── helpers ────────────────────────────────── #}

{% macro cluster_enabled() %}
  {# Returns true when cluster mode is active. #}
  {{ return(var('cluster_enabled', false) | as_bool) }}
{% endmacro %}


{% macro cluster_name() %}
  {#
    Returns the cluster name string when cluster mode is active, else none.
    Passing none to dbt-clickhouse's `cluster` config is treated as "not set"
    — no ON CLUSTER DDL is emitted, preserving single-node behaviour.
  #}
  {% if cluster_enabled() %}
    {{ return('konsol_cluster') }}
  {% else %}
    {{ return(none) }}
  {% endif %}
{% endmacro %}


{% macro cluster_zk_path() %}
  {#
    ZooKeeper / ClickHouse Keeper path template.
    ClickHouse expands the {shard}, {database}, {table} macros at CREATE time
    using the values from the <macros> section of the server config.
    See: clickhouse/cluster/macros-shard1-replica1.xml (example).
  #}
  {{ return('/clickhouse/tables/{shard}/{database}/{table}') }}
{% endmacro %}


{% macro cluster_sharding_key(col='data_area_id') %}
  {#
    Returns the sharding expression used for Distributed tables.
    cityHash64 gives even distribution; a given legal entity always routes to the
    same shard so per-LE GL history colocates. The shard column is `data_area_id`
    — the LE column materialized across bronze/silver/gold (the canonical
    `entity_id` is renamed to `data_area_id` at the bronze source boundary).
  #}
  {{ return('cityHash64(' ~ col ~ ')') }}
{% endmacro %}


{# ─────────────────────────────── engine ─────────────────────────────────── #}

{% macro cluster_engine(base_engine) %}
  {#
    Converts a plain MergeTree-family engine string to its Replicated variant
    for use on a cluster.  When cluster mode is OFF the original string is
    returned unchanged, so the single-node default compile is identical.

    Supported conversions
    ---------------------
    MergeTree()                   → ReplicatedMergeTree(zk_path, {replica})
    ReplacingMergeTree(ver)       → ReplicatedReplacingMergeTree(zk_path, {replica}, ver)
    AggregatingMergeTree()        → ReplicatedAggregatingMergeTree(zk_path, {replica})
    CollapsingMergeTree(sign)     → ReplicatedCollapsingMergeTree(zk_path, {replica}, sign)
    SummingMergeTree([cols])      → ReplicatedSummingMergeTree(zk_path, {replica}[, cols])

    Engines that are already Replicated* or Distributed are returned unchanged.

    ZK-path note
    ------------
    '{replica}' is a server-side macro; keep the surrounding single-quotes so
    ClickHouse can expand it.  Example rendered output:
      ReplicatedReplacingMergeTree(
        '/clickhouse/tables/{shard}/epm_bronze/bronze_general_journal_account_entries',
        '{replica}',
        _airbyte_extracted_at
      )
    The path segments {shard} and {database}/{table} are also expanded by the
    server from the <macros> config section at CREATE TABLE time.

    NEEDS-A-CLUSTER: Whether the Keeper paths and engine args produce correct
    per-shard replication on a real multi-node setup has NOT been verified.
  #}

  {% if not cluster_enabled() %}
    {{ return(base_engine) }}
  {% endif %}

  {% set eng = base_engine | trim %}
  {% set paren_start = eng.find('(') %}

  {% if paren_start < 0 %}
    {% set eng_name = eng | lower %}
    {% set eng_args = '' %}
  {% else %}
    {% set eng_name = eng[0:paren_start] | lower | trim %}
    {% set last_paren = eng.rfind(')') %}
    {% if last_paren > paren_start %}
      {% set eng_args = eng[paren_start + 1 : last_paren] | trim %}
    {% else %}
      {% set eng_args = '' %}
    {% endif %}
  {% endif %}

  {% set zk  = "'" ~ cluster_zk_path() ~ "'" %}
  {% set rep = "'{replica}'" %}
  {% set prefix = zk ~ ', ' ~ rep %}

  {% if eng_name == 'mergetree' %}
    {{ return('ReplicatedMergeTree(' ~ prefix ~ ')') }}

  {% elif eng_name == 'replacingmergetree' %}
    {% if eng_args %}
      {{ return('ReplicatedReplacingMergeTree(' ~ prefix ~ ', ' ~ eng_args ~ ')') }}
    {% else %}
      {{ return('ReplicatedReplacingMergeTree(' ~ prefix ~ ')') }}
    {% endif %}

  {% elif eng_name == 'aggregatingmergetree' %}
    {{ return('ReplicatedAggregatingMergeTree(' ~ prefix ~ ')') }}

  {% elif eng_name == 'collapsingmergetree' %}
    {{ return('ReplicatedCollapsingMergeTree(' ~ prefix ~ ', ' ~ eng_args ~ ')') }}

  {% elif eng_name == 'summingmergetree' %}
    {% if eng_args %}
      {{ return('ReplicatedSummingMergeTree(' ~ prefix ~ ', ' ~ eng_args ~ ')') }}
    {% else %}
      {{ return('ReplicatedSummingMergeTree(' ~ prefix ~ ')') }}
    {% endif %}

  {% else %}
    {# Already Replicated*, Distributed, or unknown — pass through unchanged. #}
    {{ return(base_engine) }}
  {% endif %}

{% endmacro %}


{% macro cluster_sharded_tables() %}
  {#
    Single source of truth for which tables get a Distributed overlay — used by
    BOTH create_distributed_tables and drop_distributed_tables so they can never
    diverge. Returns (database, table) pairs.

    Only models that are cluster-aware (carry cluster_engine()/cluster_name() in
    their config, so dbt builds a `<table>_local` ReplicatedMergeTree) may appear
    here — listing a model without a `_local` table makes create fail. To shard a
    new model: add the cluster config to the MODEL, then add its (db, table) here.

    NOTE: only a few high-volume models are cluster-aware today; this is
    intentional scaffolding. The cleaner long-term path is dbt-clickhouse's native
    `distributed_table` / `distributed_incremental` materializations (which manage
    _local + Distributed + sharding_key from model config) — see PRD §2.
  #}
  {{ return([
    ('epm_bronze', 'bronze_general_journal_account_entries'),
    ('epm_bronze', 'bronze_general_journal_entries'),
    ('epm_gold', 'gold_trial_balance')
  ]) }}
{% endmacro %}


{# ─────────────────────── distributed overlay (run-operation) ─────────────── #}

{% macro create_distributed_tables(
    cluster_name_arg='konsol_cluster',
    shard_key='data_area_id'
) %}
  {#
    Run-operation: creates Distributed overlay tables over the ReplicatedMergeTree
    local tables that dbt builds in cluster mode.

    Convention
    ----------
      epm_bronze.bronze_*_local   ← dbt model builds this (ReplicatedMergeTree)
      epm_bronze.bronze_*         ← this operation creates it (Distributed)

    The Distributed table is the query surface for the API and Cube.js.
    The _local table is INSERT-targeted by dbt and ClickHouse replication.

    Usage
    -----
      dbt run-operation create_distributed_tables
      # or, overriding defaults:
      dbt run-operation create_distributed_tables \
        --args '{"cluster_name_arg": "konsol_cluster", "shard_key": "data_area_id"}'

    NEEDS-A-CLUSTER: This operation targets a live multi-node ClickHouse cluster
    and CANNOT be verified on a single-node setup.  It is provided as DDL
    scaffolding only.  After dbt build populates the _local tables, run this
    operation once per cluster to create the routing layer.

    Idempotency: uses CREATE TABLE IF NOT EXISTS, so re-running is safe.
  #}

  {% if not cluster_enabled() %}
    {{ log(
      'create_distributed_tables: cluster_enabled is false — nothing to do. '
      ~ 'Run with --vars \'{"cluster_enabled": true}\' to activate.',
      info=True
    ) }}
    {{ return('') }}
  {% endif %}

  {% set sk = cluster_sharding_key(shard_key) %}
  {% set cn = cluster_name_arg %}

  {%- set ns = namespace(statements=[]) -%}
  {% for (db, tbl) in cluster_sharded_tables() %}
    {%- set stmt -%}
CREATE TABLE IF NOT EXISTS {{ db }}.{{ tbl }}
ON CLUSTER {{ cn }}
AS {{ db }}.{{ tbl }}_local
ENGINE = Distributed('{{ cn }}', '{{ db }}', '{{ tbl }}_local', {{ sk }})
    {%- endset -%}
    {%- set ns.statements = ns.statements + [stmt] -%}
  {% endfor %}

  {% for stmt in ns.statements %}
    {% do run_query(stmt) %}
    {{ log('Created Distributed table: ' ~ stmt.split('\n')[0], info=True) }}
  {% endfor %}

{% endmacro %}


{# ─────────────────────── drop distributed overlay (run-operation) ────────── #}

{% macro drop_distributed_tables(
    cluster_name_arg='konsol_cluster'
) %}
  {#
    Drops the Distributed overlay tables (but NOT the _local ReplicatedMergeTree
    tables).  Use before re-running create_distributed_tables to reset the
    routing layer.

    NEEDS-A-CLUSTER: Same caveat as create_distributed_tables.
  #}

  {% if not cluster_enabled() %}
    {{ log('drop_distributed_tables: cluster_enabled is false — nothing to do.', info=True) }}
    {{ return('') }}
  {% endif %}

  {% set cn = cluster_name_arg %}

  {# Same source of truth as create_distributed_tables — never diverges. #}
  {% set all_tables = cluster_sharded_tables() %}

  {% for (db, tbl) in all_tables %}
    {% do run_query('DROP TABLE IF EXISTS ' ~ db ~ '.' ~ tbl ~ ' ON CLUSTER ' ~ cn) %}
    {{ log('Dropped Distributed table: ' ~ db ~ '.' ~ tbl, info=True) }}
  {% endfor %}

{% endmacro %}
