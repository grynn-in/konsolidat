-- PRD-15 Test: Matched IC balances must have net_balance ≈ 0
select
    entity_a,
    entity_b,
    account_a,
    account_b,
    net_balance
from {{ ref('gold_ic_reconciliation') }}
where match_status = 'matched'
  and abs(net_balance) > 0.01
