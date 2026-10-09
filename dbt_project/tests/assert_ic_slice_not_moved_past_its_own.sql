-- konsolidat#245. No elimination slice may be moved further than it moved itself.
--
-- THE ASSERTION NO TEST IN THIS LAYER MAKES, and the reason five rounds of
-- guards all passed while the numbers were wrong. Every existing assertion
-- here is satisfied by construction: shares lie in [0,1] and sum to 1, so
-- "the slices sum to the leg" and "no slice exceeds the leg" cannot fail. The
-- quantity that CAN be wrong is the one none of them compares — a slice's
-- share of the leg against that slice's OWN movement.
--
-- amount_i = |leg| x aligned_i / aligned_gross, so amount_i <= aligned_i holds
-- exactly when aligned_gross >= |leg|. At leg_coverage() = 0.5 the gate allowed
-- |leg| <= 2 x aligned_gross, so a slice could take twice what it booked:
-- measured through the real chain, a cost centre that ever booked +100 ended
-- at -100, on an intercompany receivable, with the account total exactly
-- right. That is what this test exists to catch.
--
-- Only the SLICED rows are checked. A whole-leg row is blank-dimensioned by
-- design and carries the entire leg, which is the declared answer when the
-- side cannot account for it.
--
-- Error severity: a slice moved past its own movement is a wrong consolidated
-- number that every total-based check accepts.
{# Two passes, because ClickHouse refuses a window function inside an
   aggregate (ILLEGAL_AGGREGATION) — the same limit the model hit. #}
with side_net as (
    select
        consolidation_group, fiscal_year, fiscal_period, entity, partner, account,
        {{ dim_select(trailing=true) }}
        mov_group as slice_mov,
        sum(mov_group) over (
            partition by consolidation_group, fiscal_year, fiscal_period,
                         entity, partner, account
        ) as side_mov
    from {{ ref('gold_ic_side_slices') }}
),

slice_movement as (
    select
        consolidation_group,
        fiscal_year,
        fiscal_period,
        account,
        {{ dim_select(trailing=true) }}
        {# the slice's own movement, aligned with its side the way layer 2
           aligns it: a slice opposing the side's net takes no share, so its
           allowance is zero and it must receive nothing. #}
        sum(greatest(slice_mov * if(side_mov >= 0, 1, -1), 0)) as own_move
    from side_net
    group by consolidation_group, fiscal_year, fiscal_period, account
             {{ dim_group_by(leading=true) }}
),

emitted as (
    select
        consolidation_group,
        fiscal_year,
        fiscal_period,
        main_account as account,
        {{ dim_select(trailing=true) }}
        sum(abs(amount)) as moved
    from {{ ref('gold_fully_consolidated_tb') }}
    where adjustment_type in ('ic_elimination', 'ic_elimination_nci')
    group by consolidation_group, fiscal_year, fiscal_period, main_account
             {{ dim_group_by(leading=true) }}
)

select
    e.consolidation_group,
    e.fiscal_year,
    e.fiscal_period,
    e.account,
    {{ dim_select('e.', trailing=true) }}
    m.own_move,
    e.moved,
    e.moved - m.own_move as moved_past_its_own
from emitted as e
inner join slice_movement as m
    on m.consolidation_group = e.consolidation_group
    and m.fiscal_year = e.fiscal_year
    and m.fiscal_period = e.fiscal_period
    and m.account = e.account
    {% for d in var('dimensions') %}
    and m.{{ d.name }} = e.{{ d.name }}
    {%- endfor %}
{# blank-dimensioned rows are the whole-leg answer, not a sliced share #}
where {% for d in var('dimensions') %}e.{{ d.name }} != ''{{ ' or ' if not loop.last }}{% endfor %}
  {% if var('dimensions') | length == 0 %}1 = 0{% endif %}
  and e.moved > m.own_move + {{ materiality_floor() }}
