{{
    config(
        engine=cluster_engine('MergeTree()'),
        order_by='(data_area_id, fiscal_year, fiscal_period, main_account)',
        cluster=cluster_name()
    )
}}

{# F8: only CLAIMED batches exist as far as the warehouse is concerned.

   The join to the control table is the whole design: rows land in raw first
   and are claimed second, so an unclaimed batch (a crash mid-submit, a
   cancelled submission whose claim was deleted) is invisible here without any
   deletion of raw data. Resubmission is a new batch_id, never an edit.

   The claim side is GROUPed to one row per batch_id before joining: the
   control table is ReplacingMergeTree, but replacement happens at merge time,
   so a duplicated claim (an at-least-once retry) could otherwise fan out
   every raw row of the batch — debits and credits doubling together, which no
   balance test can see. #}

{# konsol#159: the intercompany partner entity on each row ('' = none). konsol
   adds the raw column (ensure_raw_tables, on submit and on every migrate) and
   init-db.sql creates it on a fresh volume. Until konsol has run once on an
   older stack the column may be missing, so it is read only if it exists:
   this model then deploys in either order with konsol#159. #}
{% set partner_expr = "''" %}
{% if execute %}
    {% set raw_columns = adapter.get_columns_in_relation(source('submission_raw', 'trial_balance_submissions')) | map(attribute='name') | list %}
    {% if 'partner_data_area_id' in raw_columns %}
        {% set partner_expr = 'raw.partner_data_area_id' %}
    {% endif %}
{% endif %}

{# konsol#255: the declared dimension values on each submitted row. Which
   dimensions exist is the `dimensions` var, never a constant, so the whole
   block is one dim_select_from_source() call over the declared list.

   Same deploy-in-either-order guard as partner_expr, for the same reason:
   konsol owns epm_raw.trial_balance_submissions and adds a dimension's column
   when the dimension is declared (ensure_raw_tables, init-db.sql). MEASURED
   22 Sep: konsol's _RAW_TABLE_DDL carries no dim_* column at all today, so
   without this guard every existing stack's bronze build would fail on an
   unknown identifier the moment a dimension is declared in dbt_project.yml.
   A dimension whose raw column konsol has not created yet reads '' — the same
   value the column's own DEFAULT gives once it is created, so the guard
   changes no row's value, only whether the SELECT can resolve.

   The declared ORDER is preserved (present and absent dimensions are not
   sorted into two blocks): each dimension's source expression is substituted
   on a copy of its entry and the one macro renders them all in var order. #}
{% set tb_dims = [] %}
{% if execute %}
    {% for d in get_dimensions() %}
        {% set g = d.copy() %}
        {% if d.source_column in raw_columns %}
            {% do g.update({'source_column': 'raw.' ~ d.source_column}) %}
        {% else %}
            {% do g.update({'source_column': "''"}) %}
        {% endif %}
        {% do tb_dims.append(g) %}
    {% endfor %}
{% endif %}

{# konsolidat#199: what the batch's amounts ARE — 'Period movement',
   'Year-to-date movement' or 'Period-end balance' — declared by konsol on the
   claim row at submit. silver_tb_movements normalises every batch to period
   movements from it. Same deploy-in-either-order guard as partner_expr: on a
   control table that predates the column every batch reads '' (undeclared),
   which assert_tb_submission_has_basis refuses rather than guessing. #}
{% set basis_expr = "''" %}
{% if execute %}
    {% set control_columns = adapter.get_columns_in_relation(source('submission_raw', 'trial_balance_submission_control')) | map(attribute='name') | list %}
    {% if 'amount_basis' in control_columns %}
        {% set basis_expr = latest_value_by('amount_basis', 'claimed_at') %}
    {% endif %}
{% endif %}

with claims as (

    select
        batch_id,
        {# alias must differ from the source column: ClickHouse resolves
           SELECT aliases inside sibling aggregates, so `as claimed_at` would
           put max() inside argMax() — ILLEGAL_AGGREGATION #}
        max(claimed_at) as last_claimed_at,
        {{ latest_value_by('row_count', 'claimed_at') }} as claimed_row_count,
        {{ basis_expr }} as amount_basis
    from {{ source('submission_raw', 'trial_balance_submission_control') }}
    group by batch_id

)

select
    raw.batch_id                                          as batch_id,
    {{ cast_to_string('raw.data_area_id') }}              as data_area_id,
    {{ cast_to_uint16('raw.fiscal_year') }}               as fiscal_year,
    {{ cast_to_uint8('raw.fiscal_period') }}              as fiscal_period,
    {{ cast_to_string('raw.main_account') }}              as main_account,
    {{ cast_to_decimal128('raw.debit_amount', 2) }}       as debit_amount,
    {{ cast_to_decimal128('raw.credit_amount', 2) }}      as credit_amount,
    {{ cast_to_string('raw.description') }}               as description,
    {{ cast_to_string(partner_expr) }}                    as partner_data_area_id,
    {# konsol#255: the declared dimensions, in var order (see tb_dims above) #}
    {{ dim_select_from_source(dims=tb_dims, trailing=true) }}
    {{ cast_to_string('raw.submission_name') }}           as submission_name,
    raw.submitted_at                                      as submitted_at,
    claims.last_claimed_at                                as claimed_at,
    claims.claimed_row_count                              as claimed_row_count,
    {{ cast_to_string('claims.amount_basis') }}           as amount_basis
from {{ source('submission_raw', 'trial_balance_submissions') }} as raw
inner join claims
    on raw.batch_id = claims.batch_id
