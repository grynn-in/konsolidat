-- konsolidat#245 Q1 A, decided by Deepak Pai on 21 Nov 2026: the intercompany DIFFERENCE entry (the
-- unmatched residual) is posted on the blank slice, on BOTH of its legs, the IC-account leg included.
-- Only the matched part of a pair carries each side's slices (option C, 6 Oct 2026). Rejected: B, keep the
-- IC-account leg sliced, which splits the unmatched part by the matched part's mix and gives a segment a
-- difference it did not produce.
--
-- Layer 2 of gold_fully_consolidated_tb carries no elimination_kind, and the matched and difference entries
-- of a pair share one journal_id (the rule_id 'IC:<account_a>/<account_b>'), so the check is a bound: on each
-- account of each pair rule, what layer 2 posts on NON-BLANK slices can be at most the matched part. The
-- allowance is the sum, over the pair's sides on that account, of the absolute matched elimination; a side
-- whose slices do not cover its leg posts it on the blank slice, which only lowers the sliced figure, so a
-- correct layer never exceeds the allowance. A difference leg on the IC account has the sign of the matched
-- leg on that account (both reduce the side's balance), so a sliced difference always pushes the sliced
-- figure past the allowance by the difference itself.
--
-- The basis is the pair's. A balance pair is eliminated to date (gold_ic_eliminations decision 14), so both
-- figures are taken to date at every period layer 2 posted a sliced row; a movement pair is compared period by
-- period. On the base, a receivable of 100 split 60 / 40 over two cost centres against a payable of 90 put the
-- residual 10 on the cost centres (-6 / -4) beside the matched -54 / -36: sliced 100 against an allowance
-- of 90.
--
-- Error severity: a sliced difference is a segment balance the segment did not book.
{% set dims = var('dimensions') %}
{% if dims | length == 0 %}
select 1 as journal_id where 0
{% else %}
with pair_rules as (
    select consolidation_group, rule_id, any(basis) as basis
    from {{ ref('gold_ic_eliminations') }}
    where rule_type = 'balance'
    group by consolidation_group, rule_id
),

{# each side's matched leg on an account, per period #}
matched_sides as (
    select consolidation_group, rule_id, debit_entity as entity, credit_entity as partner,
           debit_account as account, fiscal_year, fiscal_period, toFloat64(debit_elimination) as matched
    from {{ ref('gold_ic_eliminations') }}
    where rule_type = 'balance' and elimination_kind = 'matched'
    union all
    select consolidation_group, rule_id, credit_entity as entity, debit_entity as partner,
           credit_account as account, fiscal_year, fiscal_period, toFloat64(credit_elimination) as matched
    from {{ ref('gold_ic_eliminations') }}
    where rule_type = 'balance' and elimination_kind = 'matched'
),

{# what layer 2 posted on a non-blank slice, per rule, account and period #}
sliced as (
    select consolidation_group, journal_id as rule_id, main_account as account,
           toUInt16(fiscal_year) as fiscal_year, toUInt16(fiscal_period) as fiscal_period,
           sum(toFloat64(amount)) as sliced_amount
    from {{ ref('gold_fully_consolidated_tb') }}
    where adjustment_type = 'ic_elimination'
      and ({% for d in dims %}{{ d.name }} != ''{{ ' or ' if not loop.last }}{% endfor %})
    group by consolidation_group, journal_id, main_account, fiscal_year, fiscal_period
),

points as (
    select distinct s.consolidation_group as consolidation_group, s.rule_id as rule_id, s.account as account,
           s.fiscal_year as fiscal_year, s.fiscal_period as fiscal_period, r.basis as basis
    from sliced as s
    inner join pair_rules as r
        on r.consolidation_group = s.consolidation_group and r.rule_id = s.rule_id
),

{# the sliced figure at each point: to date for a balance pair, the period's for a movement pair #}
sliced_at as (
    select p.consolidation_group as consolidation_group, p.rule_id as rule_id, p.account as account,
           p.fiscal_year as fiscal_year, p.fiscal_period as fiscal_period,
           sum(s.sliced_amount) as sliced_td
    from points as p
    inner join sliced as s
        on s.consolidation_group = p.consolidation_group and s.rule_id = p.rule_id and s.account = p.account
    where if(p.basis = 'balance',
             (s.fiscal_year, s.fiscal_period) <= (p.fiscal_year, p.fiscal_period),
             (s.fiscal_year, s.fiscal_period) = (p.fiscal_year, p.fiscal_period))
    group by p.consolidation_group, p.rule_id, p.account, p.fiscal_year, p.fiscal_period
),

{# each side's matched elimination at each point, on the same basis #}
side_matched_at as (
    select p.consolidation_group as consolidation_group, p.rule_id as rule_id, p.account as account,
           p.fiscal_year as fiscal_year, p.fiscal_period as fiscal_period,
           m.entity as entity, m.partner as partner,
           sum(m.matched) as side_matched
    from points as p
    inner join matched_sides as m
        on m.consolidation_group = p.consolidation_group and m.rule_id = p.rule_id and m.account = p.account
    where if(p.basis = 'balance',
             (toUInt16(m.fiscal_year), toUInt16(m.fiscal_period)) <= (p.fiscal_year, p.fiscal_period),
             (toUInt16(m.fiscal_year), toUInt16(m.fiscal_period)) = (p.fiscal_year, p.fiscal_period))
    group by p.consolidation_group, p.rule_id, p.account, p.fiscal_year, p.fiscal_period, m.entity, m.partner
),

allowance as (
    select consolidation_group, rule_id, account, fiscal_year, fiscal_period,
           sum(abs(side_matched)) as matched_allowance
    from side_matched_at
    group by consolidation_group, rule_id, account, fiscal_year, fiscal_period
)

{# join_use_nulls=0: a point with no matched leg at all has allowance 0, so any sliced amount flags #}
select
    s.consolidation_group as consolidation_group,
    s.rule_id as journal_id,
    s.account as main_account,
    s.fiscal_year as fiscal_year,
    s.fiscal_period as fiscal_period,
    s.sliced_td as sliced_amount,
    a.matched_allowance as matched_allowance
from sliced_at as s
left join allowance as a
    on a.consolidation_group = s.consolidation_group and a.rule_id = s.rule_id and a.account = s.account
    and a.fiscal_year = s.fiscal_year and a.fiscal_period = s.fiscal_period
where abs(s.sliced_td) > a.matched_allowance + {{ materiality_floor() }}
{% endif %}
