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

with claims as (

    select
        batch_id,
        {# alias must differ from the source column: ClickHouse resolves
           SELECT aliases inside sibling aggregates, so `as claimed_at` would
           put max() inside argMax() — ILLEGAL_AGGREGATION #}
        max(claimed_at) as last_claimed_at,
        {{ latest_value_by('row_count', 'claimed_at') }} as claimed_row_count
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
    {{ cast_to_string('raw.submission_name') }}           as submission_name,
    raw.submitted_at                                      as submitted_at,
    claims.last_claimed_at                                as claimed_at,
    claims.claimed_row_count                              as claimed_row_count
from {{ source('submission_raw', 'trial_balance_submissions') }} as raw
inner join claims
    on raw.batch_id = claims.batch_id
