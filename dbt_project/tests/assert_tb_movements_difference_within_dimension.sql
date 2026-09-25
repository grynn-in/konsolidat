{#
    A movement is differenced against the SAME dimension combination (konsol#255).

    silver_tb_movements turns a 'Year-to-date movement' or 'Period-end balance'
    file into period movements by subtracting the previous period's figure for
    the key. Once a file carries declared dimension values, the key includes
    them: an account split across two cost centres is TWO series, and each
    period's figure belongs to one of them.

    KNOWN RED at konsol#255 row 7a-2. Both lagInFrame partitions in
    silver_tb_movements (previous_net_any_year, previous_net_same_year), its
    `keys` CTE and every join onto `source` are still keyed on
    (data_area_id, main_account, partner_data_area_id) with no dimensions —
    deliberately, see the grain note at the top of that model. So the two
    series are walked as one: a slice's figure is differenced against the
    OTHER slice's figure and every amount on the split account is wrong.
    Row 7b widens the partitions and this test turns green.

    Why the existing suite cannot see it. The differencing telescopes, so the
    error cancels within the (entity, account, partner) key:
    assert_tb_movements_cumulate_to_source runs its running sums on that same
    un-widened key and comes back exact, and a file whose slices net out
    across accounts still sums to zero per period, so
    assert_tb_movements_balance passes too. Both are measured to pass on this
    test's must_flag fixture.

    What is flagged. Per row, the previous figure the model used is exactly
    source_net_amount - movement_amount; the previous figure the FULL key
    implies is recomputed here with dim_partition_by over the declared
    dimensions. A row whose movement disagrees with the full-key figure by
    more than 0.01 is returned, with both previous figures and both movements
    side by side. predecessor_dimension_key is the un-widened window
    reconstructed over this model's output rather than its spine: it names the
    slice the row was differenced against, but two slices of one period are
    tied in that ordering, so treat it as an explanation and the two
    previous_net columns as the evidence.

    Quiet where it must be quiet. It is konsol's close-time suite that runs
    this (`dbt test --select test_type:singular`), on sites that declare no
    dimensions at all and on CI's fresh site:
      - no declared dimensions: the presence guard below returns the row-less
        branch, so nothing is computed and nothing can be flagged;
      - 'Period movement' files: not differenced at all, filtered out here;
      - an account that is not split: the full key and the un-widened key walk
        the same single series and agree.

    Out of scope, declared rather than silent: the synthesised year-end close.
    A 'year_end_close' row is computed on the un-widened key and carries BLANK
    dimensions at this commit, so it — and the first period differenced against
    it — would disagree with a full-key recomputation for a reason this test is
    not about. What a close per dimension value means is konsol#255 row 7b's
    decision; assert_year_end_close_declared / assert_year_end_close_carried
    judge the close itself. So exactly two things are left unjudged: the close
    rows, and the row whose predecessor IS a close row. They stay in both
    windows, so every other row's chain is the model's own.

    That exclusion is deliberately narrow because the alternative is not:
    measured on this warehouse's live silver_tb_movements, every one of its
    36,665 activity rows is 'Period-end balance' and 41 of its 44 entities
    carry a close, so excluding a whole entity that has one would leave this
    test judging three entities and calling itself green.

    Tolerance 0.01, as for the other movement tests.
#}

{{ config(severity='error') }}

{%- set dims = get_dimensions() %}

{% if dims | length == 0 %}

{# Presence guard: a site that declares no dimensions has one series per key by
   construction and there is nothing to cross. A typed, row-less select over the
   model rather than no query at all — it keeps the ref(), so the test still
   hangs off silver_tb_movements in the DAG and is still selected with it. #}
select
    data_area_id,
    fiscal_year,
    fiscal_period,
    main_account,
    partner_data_area_id,
    '' as dimension_key,
    '' as predecessor_dimension_key,
    amount_basis,
    source_net_amount,
    toDecimal128(0, 2) as previous_net_used,
    toDecimal128(0, 2) as previous_net_within_dimension,
    movement_amount,
    toDecimal128(0, 2) as movement_within_dimension,
    toDecimal128(0, 2) as difference
from {{ ref('silver_tb_movements') }}
where 0

{% else %}

with judged as (

    {# only the two bases that difference; a 'Period movement' row's movement is
       its own net whatever the key. The dimension key is built from the declared
       list, never from literal column names #}
    select
        data_area_id,
        fiscal_year,
        fiscal_period,
        main_account,
        partner_data_area_id,
        {{ dim_select(trailing=true) }}
        concat({% for d in dims %}'|', {{ d.name }}{{ ', ' if not loop.last }}{% endfor %}) as dimension_key,
        amount_basis,
        movement_kind,
        source_net_amount,
        movement_amount
    from {{ ref('silver_tb_movements') }}
    where amount_basis in ('Year-to-date movement', 'Period-end balance')

),

compared as (

    select
        *,
        {# the previous figure the FULL key implies: the model's windows widened
           with the declared dimensions #}
        lagInFrame(source_net_amount, 1, toDecimal128(0, 2)) over (
            partition by data_area_id, main_account, partner_data_area_id{{ dim_partition_by(leading=true) }}
            order by fiscal_year, fiscal_period
            rows between unbounded preceding and current row
        ) as within_previous_net_any_year,
        lagInFrame(source_net_amount, 1, toDecimal128(0, 2)) over (
            partition by data_area_id, main_account, partner_data_area_id{{ dim_partition_by(leading=true) }}, fiscal_year
            order by fiscal_period
            rows between unbounded preceding and current row
        ) as within_previous_net_same_year,
        {# the close is not judged here: the row it was differenced against #}
        lagInFrame(movement_kind, 1, '') over (
            partition by data_area_id, main_account, partner_data_area_id
            order by fiscal_year, fiscal_period
            rows between unbounded preceding and current row
        ) as model_previous_movement_kind,
        {# the slice the un-widened window reaches for (explanation only) #}
        lagInFrame(dimension_key, 1, '') over (
            partition by data_area_id, main_account, partner_data_area_id
            order by fiscal_year, fiscal_period
            rows between unbounded preceding and current row
        ) as model_previous_key_any_year,
        lagInFrame(dimension_key, 1, '') over (
            partition by data_area_id, main_account, partner_data_area_id, fiscal_year
            order by fiscal_period
            rows between unbounded preceding and current row
        ) as model_previous_key_same_year
    from judged

)

select
    data_area_id,
    fiscal_year,
    fiscal_period,
    main_account,
    partner_data_area_id,
    dimension_key,
    if(amount_basis = 'Year-to-date movement',
       model_previous_key_same_year,
       model_previous_key_any_year) as predecessor_dimension_key,
    amount_basis,
    source_net_amount,
    {# exact, from the model's own arithmetic: no window can disagree with it #}
    source_net_amount - movement_amount as previous_net_used,
    if(amount_basis = 'Year-to-date movement',
       within_previous_net_same_year,
       within_previous_net_any_year) as previous_net_within_dimension,
    movement_amount,
    source_net_amount - previous_net_within_dimension as movement_within_dimension,
    round(movement_amount - movement_within_dimension, 2) as difference
from compared
where movement_kind = 'activity'
  and model_previous_movement_kind != 'year_end_close'
  and abs(difference) > 0.01

{% endif %}
