{{
    config(
        engine='MergeTree()',
        order_by='(data_area_id, fiscal_year, fiscal_period, main_account)'
    )
}}

{# F8: only CLAIMED batches exist as far as the warehouse is concerned.

   The INNER JOIN to the control table is the whole design: rows land in raw
   first and are claimed second, so an unclaimed batch (a crash mid-submit, a
   cancelled submission whose claim was deleted) is invisible here without any
   deletion of raw data. Resubmission is a new batch_id, never an edit. #}

select
    raw.batch_id                                          as batch_id,
    {{ cast_to_string('raw.data_area_id') }}              as data_area_id,
    {{ cast_to_uint16('raw.fiscal_year') }}               as fiscal_year,
    toUInt8(raw.fiscal_period)                            as fiscal_period,
    {{ cast_to_string('raw.main_account') }}              as main_account,
    {{ cast_to_decimal128('raw.debit_amount', 2) }}       as debit_amount,
    {{ cast_to_decimal128('raw.credit_amount', 2) }}      as credit_amount,
    {{ cast_to_string('raw.description') }}               as description,
    {{ cast_to_string('raw.submission_name') }}           as submission_name,
    raw.submitted_at                                      as submitted_at,
    ctl.claimed_at                                        as claimed_at
from {{ source('submission_raw', 'trial_balance_submissions') }} as raw
inner join {{ source('submission_raw', 'trial_balance_submission_control') }} as ctl
    on raw.batch_id = ctl.batch_id
