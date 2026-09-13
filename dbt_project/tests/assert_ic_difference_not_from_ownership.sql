{#
    Decision 12 (13 Sep 2026): ownership never produces an intercompany
    difference.

    Each pair's two sides are recomputed from gold_consolidated_trial_balance
    at 100% (translated_amount), never the ownership-weighted group_amount.
    Fails when:
    - difference: the pair's difference is not the sum of its two 100% sides;
    - ownership: the sides net to zero at 100% but the pair is not matched
      with difference 0. For example, 1000 at a 100%-owned entity against
      1000 at an 80%-owned one is matched, although the group view holds
      1000 and 800.
#}

with expected as (
    {{ ic_expected_pair_values() }}
)

select
    if(abs(e.expected_a + e.expected_b) < 0.005, 'ownership', 'difference') as failed_check,
    r.consolidation_group as consolidation_group,
    r.fiscal_year as fiscal_year,
    r.fiscal_period as fiscal_period,
    concat(r.entity_a, '/', r.account_a, ' <> ', r.entity_b, '/', r.account_b) as detail,
    r.difference as difference,
    e.expected_a + e.expected_b as difference_at_100pct,
    r.match_status as match_status
from {{ ref('gold_ic_reconciliation') }} as r
inner join expected as e
    on e.consolidation_group = r.consolidation_group and e.fiscal_year = r.fiscal_year
    and e.fiscal_period = r.fiscal_period and e.entity_a = r.entity_a and e.account_a = r.account_a
    and e.entity_b = r.entity_b and e.account_b = r.account_b
where abs(r.difference - (e.expected_a + e.expected_b)) > 0.01
   or (abs(e.expected_a + e.expected_b) < 0.005
       and (r.match_status != 'matched' or abs(r.difference) >= 0.005))
