-- PRD-10 Test: accounts translated at the historical rate should produce no CTA
-- contribution (they are excluded from the CTA calculation).
-- konsolidat#213: the flag that means "declared at the historical rate" is
-- uses_historical_rate (fx_method = 'historical'). is_equity now says what the
-- account IS (account_type = 'Equity') — the meaning konsol's deal layer uses —
-- and never decided translation.
select
    consolidation_group,
    data_area_id,
    main_account,
    cta_amount
from {{ ref('gold_fx_revaluation') }}
where main_account in (
    select main_account_id from {{ ref('silver_main_accounts') }} where uses_historical_rate = 1
)
  and abs(cta_amount) > 0.01
