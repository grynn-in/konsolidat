{{
    config(
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# konsol#348 (QA1 c, konsolidat#221): the ledger flow is the trial-balance submission alone. The ERP branch
   (bronze_general_journal_account_entries, dated through the ERP fiscal calendar in silver_fiscal_periods)
   is removed: every ERP bronze table held 0 rows, and the declared calendar is the one source of period
   dates. The column list and order are the ones the two branches shared, so no reader changes. #}

{# F8: submitted trial balances enter the ledger flow HERE, as one GL-shaped
   row per account. A submission is already at trial-balance grain (period
   totals per account), which is exactly what gold_trial_balance aggregates GL
   entries down to — so shaping each row as a single synthetic entry lets
   every downstream model work unchanged, with no fork in the gold layer.

   konsolidat#199: the rows come from silver_tb_movements, not bronze. Every
   downstream reader treats a GL entry as a PERIOD MOVEMENT (gold_balance_sheet
   running sums, gold_ytd_trial_balance), but an ERP exports period movements,
   year-to-date movements or period-end balances. silver_tb_movements undoes
   the batch's declared amount_basis once, on a spine of entity periods x
   entity keys, so this branch only ever sees movements — a balance file's
   vanished account arrives here as the reversing movement it is.

   Only CLAIMED batches reach bronze_trial_balance_submissions and hence
   silver_tb_movements, so cancellation removes a submission from here
   without any delete.

   konsol#255: dimensions come from dim_select() on the submission row. (It was
   dim_empty_strings() until #255: a submitted trial balance carried no
   dimensions at all.)

   accounting_date is the declared start_date of the period in konsol's fiscal
   calendar (konsol#348): an April-March site's FY2026 P1 is 2025-04-01, not
   2026-01-01. A period the calendar does not declare is dated 1970-01-01 and
   named by the tests (see period_start below). One computed date serves
   accounting_date and document_date. #}

{% set tbs_marker = 'Trial Balance Submission' %}
select
    -- strictly negative synthetic id (it was kept apart from the positive ERP
    -- recids, and stays negative so no existing recid changes). silver_tb_movements is one row per (entity, period, account,
    -- partner, <declared dimensions>) whatever the batch held, so that key IS
    -- the identity: batch_id left the hash because a spine row (an account that
    -- vanished from a balance file) belongs to the period, not to a row of the
    -- batch, and description left because the key already sums a batch's two
    -- rows for one account into one movement.
    -- konsol#255 row 7b: the DIMENSIONS ARE IN THE HASH. Since row 7a-1 a file
    -- may split an account across dimension values, and silver_tb_movements
    -- (row 7b) now emits one row per slice — hashing the un-widened key gave
    -- every slice of one account the SAME recid. Driven by the `dimensions`
    -- var, never a literal column name; a site that declares none hashes
    -- exactly the pre-#255 key, so no existing recid changes.
    -toInt64(bitShiftRight(cityHash64(tbs.data_area_id, tbs.fiscal_year, tbs.fiscal_period, tbs.main_account, tbs.partner_data_area_id{{ dim_select(prefix='tbs.', leading=true) }}), 1)) as recid,
    tbs.data_area_id as data_area_id,
    tbs.period_start as accounting_date,
    toUInt16(tbs.fiscal_year) as fiscal_year,
    {# UInt16, the type the ERP branch fixed for this column; silver_tb_movements carries UInt8 #}
    toUInt16(tbs.fiscal_period) as fiscal_period,
    tbs.main_account as main_account,
    ma.account_name as account_name,
    ma.account_type_name as account_type_name,
    ma.is_balance_sheet as is_balance_sheet,
    ma.is_pnl as is_pnl,
    tbs.net_amount as accounting_currency_amount,
    {# a submission has no already-translated figure (an ERP row carried
       D365's here); the convention is 0 — NOT the local amount, which
       would let a consumer sum untranslated currencies believing them
       translated. Consolidation retranslates from debit/credit itself. #}
    toDecimal128(0, {{ amount_scale() }}) as reporting_currency_amount,
    tbs.net_amount as transaction_currency_amount,
    '' as transaction_currency_code,
    {# silver_tb_movements already split the movement into debit/credit
       (greatest(movement, 0) / greatest(-movement, 0)) — no sign derivation #}
    tbs.credit_amount as credit_amount,
    tbs.debit_amount as debit_amount,
    '{{ tbs_marker }}' as posting_type,
    tbs.description as description,
    tbs.partner_data_area_id as partner_data_area_id,
    {# the submitted file's own declared dimension values (konsol#255) #}
    {{ dim_select(prefix='tbs.', trailing=true) }}
    concat('TBS-', tbs.batch_id) as journal_number,
    '{{ tbs_marker }}' as journal_category,
    tbs.submission_name as document_number,
    tbs.period_start as document_date,
    {# the synthetic year-end close of a period-end-balance file (PR 200
       finding 1) is the one TBS entry that is not the file's own activity:
       it posts in the year's Closing period with batch_id '' (journal
       'TBS-') and submission 'Year-end close', and is marked here the way
       D365 marks its closing entries — on posting_layer #}
    if(tbs.movement_kind = 'year_end_close', 'Year-end close', '') as posting_layer
from (
    {# one normalised period movement per key (konsolidat#199); the batch and
       submission the period was claimed under ride along for the journal
       columns #}
    select
        m.batch_id as batch_id,
        m.movement_kind as movement_kind,
        m.data_area_id as data_area_id,
        m.fiscal_year as fiscal_year,
        m.fiscal_period as fiscal_period,
        m.main_account as main_account,
        m.debit_amount as debit_amount,
        m.credit_amount as credit_amount,
        m.description as description,
        m.partner_data_area_id as partner_data_area_id,
        {{ dim_select(prefix='m.', trailing=true) }}
        m.submission_name as submission_name,
        m.movement_amount as net_amount,
        {# konsol#348 (QA1 c / A11): the declared start_date of the period in konsol's fiscal calendar
           (macros/declared_periods.sql), the one source of period dates; no ERP calendar and no calendar-month
           guess. A period the calendar does not declare misses the LEFT JOIN and, under join_use_nulls=0,
           reads Date's default 1970-01-01. The row is KEPT, so assert_trial_balance_period_declared and
           assert_tb_submission_period_start_not_epoch name it; nothing is invented for the period. #}
        dp.start_date as period_start
    from {{ ref('silver_tb_movements') }} as m
    left join {{ declared_periods() }} as dp
        on dp.fiscal_year = toUInt16(m.fiscal_year)
        and dp.fiscal_period = toUInt16(m.fiscal_period)
) as tbs
left join {{ ref('silver_main_accounts') }} as ma
    on tbs.main_account = ma.main_account_id
