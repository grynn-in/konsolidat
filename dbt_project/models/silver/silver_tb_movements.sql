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
   partner_data_area_id, <the declared dimensions>) — one row per key and
   period, whatever the batch held. Which dimensions those are is the
   `dimensions` var; a site that declares none has the pre-#255 grain exactly.

   konsol#255 row 7b: the differencing is keyed on THAT FULL KEY. Both
   lagInFrame partitions below and the `keys` CTE carry the declared dimensions
   (dim_partition_by / dim_select over the var — never a literal column name),
   so an account split across two dimension values is two series and each
   period's figure is differenced against its own slice's previous figure. Row
   7a-1 (2d8ad1e) made the values travel and deliberately left this un-widened;
   row 7a-2 (0ca2b59) asserted it broken; this is where it is fixed, and
   assert_tb_movements_difference_within_dimension is what holds it fixed.

   konsol#255 row 17 — THE YEAR-END CLOSE IS ON THAT SAME FULL KEY. Row 7b
   widened the differencing but left the close computed on the un-widened key
   and carrying blank dimension values, and the two halves contradicted: the
   close row of an account a file splits across dimension values was the
   account's WHOLE balance differenced against the blank slice's previous
   figure — which does not exist — so the close emitted the sum of the non-blank
   slices as a movement no file ever stated (measured: an unchanged account came
   out at 200 against a stated 100), while a split P&L account was never
   reversed at all and the next year's first period read last year's result as
   activity. close_spine now enumerates the same widened `keys` and joins
   `source` on the same full key, so every close row is differenced against its
   own slice's previous figure, exactly as an activity row is.

   The one thing that does NOT carry dimension values is the retained-earnings
   line: the year's result moves into it as ONE undimensioned lump, on the blank
   key (`retained_lump_key` above, close_spine below). Decision of 23 September
   2026, Deepak Pai, in his words "one lump, no dimensions" (konsol#255) — the
   OFF default of `Dimension.survives_close`, which is what the live year-end
   entries already do: a single entity-level account with no dimension values on
   it. The ON branch — retained earnings credited per dimension value, so the
   profit keeps the values it was earned in — is NOT BUILT: there is no hook for
   it here and no half-wired field. It is a separate job, and when it lands
   `retained_lump_key` is the only thing in this model it changes.

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

   The year-end close (PR 200 finding 1): a 'Period-end balance' file carries
   the year's P&L in its accounts until the year end, and the next year's file
   starts them from zero with the result moved into retained earnings — the
   ERP's close, which no file shows. Differencing across the year end would
   read that as activity (the whole year's P&L reversed in the next first
   period). So for every entity-year of period-end balances that a later year
   follows, the model synthesizes a POST-CLOSE PERIOD in the year's Closing
   period (epm_staging.fiscal_periods, period_type = 'Closing'): the balances
   of the year's last claimed period with every P&L key
   (silver_main_accounts.is_pnl = 1) set to 0 and the retained-earnings key
   (is_retained_earnings = 1, partner '') increased by the sum of those P&L
   balances. It enters the spine as one more period (batch_id '', submission
   'Year-end close', has_source only on the retained-earnings key); the
   differencing then yields the closing entry there (movement_kind =
   'year_end_close': P&L keys reversed, retained earnings moved) and, in the
   next year's first period, activity only. The rest is movement_kind =
   'activity'. When the year has no Closing period sorting after its last
   claimed period, the chart has no (or more than one) retained-earnings
   account, or the entity itself claimed a batch in the Closing period (the
   file already holds the closed balances), nothing is synthesized;
   assert_year_end_close_declared names the first two for years with any
   non-zero P&L balance at their last claimed period. The flagged retained-earnings account must be the one the
   ERP's next file carries the result in, or the spine reverses the close as
   activity in the next first period; assert_year_end_close_carried (warn)
   names that.

   Mixed bases: each period is computed with ITS batch's basis and no attempt is
   made to reconcile a history whose batches disagree —
   assert_entity_has_one_amount_basis refuses such an entity. A basis outside
   the three strings ('' = undeclared) is read as a period movement, the
   pre-#199 reading, and assert_tb_submission_has_basis stops the build before
   that reading reaches anyone: it is an error-severity test on bronze, and
   `dbt build` skips the children of a failed error test, this model included. #}

{# konsol#255 row 17: THE key the year-end result is moved onto — the chart's
   retained-earnings account, no partner, and every declared dimension blank.
   Written once and used twice in close_spine (the figure and its has_source
   flag) so the two can never drift apart. The blank-dimension test is what
   makes the close's credit ONE LUMP: a file that split retained earnings
   across dimension values would otherwise take the year's result once per
   slice. Driven by the `dimensions` var, never a literal dimension name; on a
   site that declares none it renders exactly the pre-#255 condition. #}
{%- set retained_lump_key -%}
k.main_account = y.retained_account and k.partner_data_area_id = ''{% for d in get_dimensions() %} and k.{{ d.name }} = ''{% endfor %}
{%- endset -%}

with source as (

    {# bronze rows summed to the key: a batch may legitimately carry two rows
       for one account (different descriptions) #}
    select
        data_area_id,
        fiscal_year,
        fiscal_period,
        main_account,
        partner_data_area_id,
        {# konsol#255: the dimensions are part of the SUMMED key here, so a
           file that splits an account across dimension values keeps them
           apart — and claimed_spine joins onto this CTE on that same full key
           (row 7b). #}
        {{ dim_select(trailing=true) }}
        sum(debit_amount - credit_amount) as source_net_amount,
        if(uniqExact(description) = 1, any(description), '') as description,
        toUInt8(1) as has_source
    from {{ ref('bronze_trial_balance_submissions') }}
    group by data_area_id, fiscal_year, fiscal_period, main_account, partner_data_area_id{{ dim_group_by(leading=true) }}

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

closing_periods as (

    {# the fiscal calendar's Closing period per year (konsol owns the table);
       the first one when a calendar declares several #}
    select
        fiscal_year,
        min(fiscal_period) as closing_period
    from {{ source('epm_staging', 'fiscal_periods') }}
    where period_type = 'Closing'
    group by fiscal_year

),

retained_earnings as (

    {# the chart's retained-earnings account: usable only when there is exactly one #}
    select
        count() as retained_accounts,
        any(main_account_id) as main_account
    from {{ ref('silver_main_accounts') }}
    where is_retained_earnings = 1

),

entity_years as (

    select
        data_area_id,
        fiscal_year,
        max(fiscal_period) as last_period,
        argMax(amount_basis, fiscal_period) as amount_basis,
        groupUniqArray(fiscal_period) as claimed_periods
    from periods
    group by data_area_id, fiscal_year

),

years_to_close as (

    {# entity-years of period-end balances that a later year follows and that
       can be closed: a Closing period the entity did not claim a batch in
       and that sorts AFTER the year's last claimed period, and one
       retained-earnings account. The ordering condition (PR 200 re-review
       finding 3): the differencing walks periods in (fiscal_year,
       fiscal_period) order, so a close numbered before the balances it
       closes would be differenced against the wrong side; nothing is
       synthesized then, and assert_year_end_close_declared names the year #}
    select
        y.data_area_id as data_area_id,
        y.fiscal_year as fiscal_year,
        y.last_period as last_period,
        y.amount_basis as amount_basis,
        cp.closing_period as closing_period,
        re.main_account as retained_account
    from (
        select *, max(fiscal_year) over (partition by data_area_id) as last_year
        from entity_years
    ) as y
    inner join closing_periods as cp
        on cp.fiscal_year = y.fiscal_year
    cross join retained_earnings as re
    where y.amount_basis = 'Period-end balance'
      and y.fiscal_year < y.last_year
      and not has(y.claimed_periods, cp.closing_period)
      and cp.closing_period > y.last_period
      and re.retained_accounts = 1

),

pnl_totals as (

    {# the year's result still sitting in the P&L accounts at the last claimed period #}
    select
        y.data_area_id as data_area_id,
        y.fiscal_year as fiscal_year,
        sum(s.source_net_amount) as pnl_total
    from years_to_close as y
    inner join source as s
        on s.data_area_id = y.data_area_id
        and s.fiscal_year = y.fiscal_year
        and s.fiscal_period = y.last_period
    inner join {{ ref('silver_main_accounts') }} as ma
        on ma.main_account_id = s.main_account
    where ma.is_pnl = 1
    group by y.data_area_id, y.fiscal_year

),

keys as (

    {# konsol#255 row 7b: the key of the differencing carries the declared
       dimensions. NOT a cross join — `select distinct` over the submitted rows
       enumerates only the (account, partner, dimension) combinations that
       ACTUALLY occur in the entity's files, so the spine below grows by the
       number of real combinations, not by the product of each dimension's
       cardinality. A site that declares no dimensions renders exactly the
       pre-#255 list. #}
    select distinct
        data_area_id,
        main_account,
        partner_data_area_id{{ dim_select(leading=true) }}
    from {{ ref('bronze_trial_balance_submissions') }}

    union distinct

    {# the retained-earnings key of every entity that gets a close, whether or
       not a file ever listed it. Blank dimensions: this is the key the year's
       result is moved onto as one lump (`retained_lump_key` at the top), so it
       has to exist even on an entity whose files never mention the account #}
    select distinct
        data_area_id,
        retained_account as main_account,
        '' as partner_data_area_id{{ dim_empty_strings(leading=true) }}
    from years_to_close

),

claimed_spine as (

    {# entity periods x entity keys; a key with no source row reads 0 (ClickHouse
       LEFT JOIN fills the unmatched side with column defaults, not NULL) #}
    select
        p.data_area_id as data_area_id,
        p.fiscal_year as fiscal_year,
        p.fiscal_period as fiscal_period,
        k.main_account as main_account,
        k.partner_data_area_id as partner_data_area_id,
        {# konsol#255 row 7b: the dimension values come from the KEY, not from
           the matched source row — a key with no source row in this period
           still has to be the same series in the windows below, and s.* would
           read '' there (ClickHouse fills an unmatched LEFT JOIN side with the
           column default). POSITIONAL TWIN: close_spine below must emit its
           dimension block in this same position, the union binds by position.

           Written out rather than dim_select(prefix='k.'): that macro emits no
           alias, so the column would be NAMED `k.dim_…` and the widened
           partition by below cannot see it (measured — ClickHouse
           UNKNOWN_IDENTIFIER in scope `differenced`). Still driven by the
           `dimensions` var, no literal dimension name anywhere #}
        {% for d in get_dimensions() -%}
        k.{{ d.name }} as {{ d.name }},
        {% endfor -%}
        p.amount_basis as amount_basis,
        p.batch_id as batch_id,
        p.submission_name as submission_name,
        s.description as description,
        s.source_net_amount as source_net_amount,
        s.has_source as has_source,
        'activity' as movement_kind
    from periods as p
    inner join keys as k
        on p.data_area_id = k.data_area_id
    left join source as s
        on s.data_area_id = p.data_area_id
        and s.fiscal_year = p.fiscal_year
        and s.fiscal_period = p.fiscal_period
        and s.main_account = k.main_account
        and s.partner_data_area_id = k.partner_data_area_id
        {{ dim_join_on('s', 'k') }}

),

close_spine as (

    {# the synthetic post-close period: the last claimed period's balances,
       P&L keys at 0, retained earnings carrying the year's result. Only the
       retained-earnings key counts as sourced (and only when there is a
       result to move); every other key is a carried figure that differences
       to 0 and is dropped, or a P&L key whose reversal is the close #}
    select
        y.data_area_id as data_area_id,
        y.fiscal_year as fiscal_year,
        y.closing_period as fiscal_period,
        k.main_account as main_account,
        k.partner_data_area_id as partner_data_area_id,
        {# konsol#255 row 17: positional twin of claimed_spine's dimension
           block, and — the fix — over the SAME key. The close is one more
           period in the same series as every other: a key's post-close figure
           is differenced against THAT KEY's own previous figure by the widened
           windows below, so the two halves of the close can no longer
           contradict each other. A P&L key is zeroed in the dimension value it
           was stated in, which is the only way its balance can reach zero and
           the only way the next year's first period can start from zero.

           What does NOT carry dimension values is the retained-earnings line:
           the year's result moves into it as ONE undimensioned lump, on the
           blank key, whatever dimension values it was earned in. Decision of
           23 September 2026, Deepak Pai, in his words "one lump, no
           dimensions" (konsol#255) — the OFF default of
           `Dimension.survives_close`, and what the live year-end entries
           already do: a single entity-level account with no dimension values
           on it. The ON branch (retained earnings credited per dimension
           value, keeping where the profit came from) is NOT built and has no
           hook here; it is a separate job, and `survives_close` is the only
           thing that will change this line. #}
        {% for d in get_dimensions() -%}
        k.{{ d.name }} as {{ d.name }},
        {% endfor -%}
        y.amount_basis as amount_basis,
        '' as batch_id,
        'Year-end close' as submission_name,
        '' as description,
        multiIf(
            ma.is_pnl = 1, toDecimal128(0, 2),
            {{ retained_lump_key }},
                s.source_net_amount + t.pnl_total,
            s.source_net_amount
        ) as source_net_amount,
        toUInt8(({{ retained_lump_key }}) and t.pnl_total != 0) as has_source,
        'year_end_close' as movement_kind
    from years_to_close as y
    inner join keys as k
        on k.data_area_id = y.data_area_id
    left join pnl_totals as t
        on t.data_area_id = y.data_area_id
        and t.fiscal_year = y.fiscal_year
    left join source as s
        on s.data_area_id = y.data_area_id
        and s.fiscal_year = y.fiscal_year
        and s.fiscal_period = y.last_period
        and s.main_account = k.main_account
        and s.partner_data_area_id = k.partner_data_area_id
        {{ dim_join_on('s', 'k') }}
    left join {{ ref('silver_main_accounts') }} as ma
        on ma.main_account_id = k.main_account

),

spine as (

    select * from claimed_spine
    union all
    select * from close_spine

),

differenced as (

    select
        *,
        {# previous claimed period of the key, any year: the 'Period-end balance' rule.
           konsol#255 row 7b: the declared dimensions are part of the partition,
           so a slice is only ever differenced against its own previous figure #}
        lagInFrame(source_net_amount, 1, toDecimal128(0, 2)) over (
            partition by data_area_id, main_account, partner_data_area_id{{ dim_partition_by(leading=true) }}
            order by fiscal_year, fiscal_period
            rows between unbounded preceding and current row
        ) as previous_net_any_year,
        {# previous claimed period of the key within the fiscal year: the 'Year-to-date movement' rule #}
        lagInFrame(source_net_amount, 1, toDecimal128(0, 2)) over (
            partition by data_area_id, main_account, partner_data_area_id{{ dim_partition_by(leading=true) }}, fiscal_year
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
        {{ dim_select(trailing=true) }}
        amount_basis,
        batch_id,
        submission_name,
        description,
        source_net_amount,
        has_source,
        movement_kind,
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
    {# konsol#255: the dimensions reach the output and are part of the grain —
       see the grain note at the top #}
    {{ dim_select(trailing=true) }}
    amount_basis,
    batch_id,
    submission_name,
    description,
    source_net_amount,
    movement_amount,
    greatest(movement_amount, toDecimal128(0, 2)) as debit_amount,
    greatest(-movement_amount, toDecimal128(0, 2)) as credit_amount,
    movement_kind
from movements
where not (movement_amount = 0 and has_source = 0)
