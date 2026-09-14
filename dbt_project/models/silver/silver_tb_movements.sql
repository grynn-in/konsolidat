{{
    config(
        materialized='table',
        engine='MergeTree()',
        order_by='(data_area_id, fiscal_year, fiscal_period, main_account)'
    )
}}

{# konsolidat#199: every claimed trial-balance batch, normalised to PERIOD
   MOVEMENTS — the one shape the rest of the warehouse reads (gold_balance_sheet
   running sums, gold_ytd_trial_balance, PRD-22). An ERP exports period
   movements, year-to-date movements or period-end balances; konsol declares
   which on the claim row (amount_basis) and this model undoes the declared
   shape once, here, so nothing downstream changes.

   Grain: (data_area_id, fiscal_year, fiscal_period, main_account,
   partner_data_area_id) — one row per key and period, whatever the batch held.

   The three rules, per key, periods ordered by (fiscal_year, fiscal_period)
   among the periods the ENTITY has a claimed batch for:
     'Period movement'        movement = net(p)                    (net = debit - credit)
     'Year-to-date movement'  movement = net(p) - net(previous period of the SAME fiscal
                              year); first period of a year: net(p)
     'Period-end balance'     movement = net(p) - net(previous claimed period, any year);
                              first claimed period: net(p) (the balance from inception)

   The spine: a balance or YTD file only lists the keys that are non-zero,
   so a key present in an earlier period and absent later has net 0 there and
   its movement is minus the previous figure (a loan repaid vanishes from the
   file; the repayment is a movement). Differencing rows that exist would miss
   it. So the model works on entity periods x entity keys and reads a missing
   source row as 0; spine rows that end with movement 0 and no source row are
   dropped again, so a 'Period movement' batch comes out exactly as landed.

   Mixed bases: each period is computed with ITS batch's basis and no attempt is
   made to reconcile a history whose batches disagree —
   assert_entity_has_one_amount_basis refuses such an entity. A basis outside
   the three strings ('' = undeclared) is read as a period movement, the
   pre-#199 reading, and assert_tb_submission_has_basis stops the build before
   that reading reaches anyone. #}

with source as (

    {# bronze rows summed to the key: a batch may legitimately carry two rows
       for one account (different descriptions) #}
    select
        data_area_id,
        fiscal_year,
        fiscal_period,
        main_account,
        partner_data_area_id,
        sum(debit_amount - credit_amount) as source_net_amount,
        if(uniqExact(description) = 1, any(description), '') as description,
        toUInt8(1) as has_source
    from {{ ref('bronze_trial_balance_submissions') }}
    group by data_area_id, fiscal_year, fiscal_period, main_account, partner_data_area_id

),

periods as (

    {# the entity's claimed periods, each with its batch and declared basis
       (one batch per entity-period: assert_tb_submission_single_batch_per_period;
       the latest claim is taken should that ever be violated) #}
    select
        data_area_id,
        fiscal_year,
        fiscal_period,
        argMax(batch_id, claimed_at) as batch_id,
        argMax(submission_name, claimed_at) as submission_name,
        argMax(amount_basis, claimed_at) as amount_basis
    from {{ ref('bronze_trial_balance_submissions') }}
    group by data_area_id, fiscal_year, fiscal_period

),

keys as (

    select distinct
        data_area_id,
        main_account,
        partner_data_area_id
    from {{ ref('bronze_trial_balance_submissions') }}

),

spine as (

    {# entity periods x entity keys; a key with no source row reads 0 (ClickHouse
       LEFT JOIN fills the unmatched side with column defaults, not NULL) #}
    select
        p.data_area_id as data_area_id,
        p.fiscal_year as fiscal_year,
        p.fiscal_period as fiscal_period,
        k.main_account as main_account,
        k.partner_data_area_id as partner_data_area_id,
        p.amount_basis as amount_basis,
        p.batch_id as batch_id,
        p.submission_name as submission_name,
        s.description as description,
        s.source_net_amount as source_net_amount,
        s.has_source as has_source
    from periods as p
    inner join keys as k
        on p.data_area_id = k.data_area_id
    left join source as s
        on s.data_area_id = p.data_area_id
        and s.fiscal_year = p.fiscal_year
        and s.fiscal_period = p.fiscal_period
        and s.main_account = k.main_account
        and s.partner_data_area_id = k.partner_data_area_id

),

differenced as (

    select
        *,
        {# previous claimed period of the key, any year: the 'Period-end balance' rule #}
        lagInFrame(source_net_amount, 1, toDecimal128(0, 2)) over (
            partition by data_area_id, main_account, partner_data_area_id
            order by fiscal_year, fiscal_period
            rows between unbounded preceding and current row
        ) as previous_net_any_year,
        {# previous claimed period of the key within the fiscal year: the 'Year-to-date movement' rule #}
        lagInFrame(source_net_amount, 1, toDecimal128(0, 2)) over (
            partition by data_area_id, main_account, partner_data_area_id, fiscal_year
            order by fiscal_period
            rows between unbounded preceding and current row
        ) as previous_net_same_year
    from spine

),

movements as (

    select
        data_area_id,
        fiscal_year,
        fiscal_period,
        main_account,
        partner_data_area_id,
        amount_basis,
        batch_id,
        submission_name,
        description,
        source_net_amount,
        has_source,
        multiIf(
            amount_basis = 'Year-to-date movement', source_net_amount - previous_net_same_year,
            amount_basis = 'Period-end balance', source_net_amount - previous_net_any_year,
            source_net_amount
        ) as movement_amount
    from differenced

)

select
    data_area_id,
    fiscal_year,
    fiscal_period,
    main_account,
    partner_data_area_id,
    amount_basis,
    batch_id,
    submission_name,
    description,
    source_net_amount,
    movement_amount,
    greatest(movement_amount, toDecimal128(0, 2)) as debit_amount,
    greatest(-movement_amount, toDecimal128(0, 2)) as credit_amount
from movements
where not (movement_amount = 0 and has_source = 0)
