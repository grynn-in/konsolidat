-- PRD-10 Test: Equity accounts translated at historical rate should produce
-- no CTA contribution (they are excluded from CTA calculation via is_equity flag)
-- This test checks the fx_revaluation model excludes equity accounts
select
    consolidation_group,
    data_area_id,
    main_account,
    cta_amount
from {{ ref('gold_fx_revaluation') }}
where main_account in (
    select main_account_id from {{ ref('silver_main_accounts') }} where is_equity = 1
)
  and abs(cta_amount) > 0.01
