-- PRD-2 Test: CTA must be non-zero when an entity-period translated at more than one rate.
--
-- What CTA is: gold_fx_revaluation.cta_amount is the residual of currency translation,
-- -sum(group_amount) per entity-period. Balance-sheet rows translate at the closing
-- rate, P&L rows at the average rate and (with an approved Historical Equity Rate)
-- equity rows at that historical rate. Because the local trial balance sums to zero,
-- the translated one only fails to when more than one rate was applied; that gap is
-- the CTA.
--
-- When CTA must be non-zero: an entity-period in which at least one row translated at
-- a rate other than its closing_rate. A zero CTA there means gold_fx_revaluation lost
-- the residual, and this test flags it.
--
-- Why a rate difference alone is not enough: closing_rate != average_rate only says
-- two rates were *available*. A balance-sheet-only entity (no P&L rows, no historical
-- equity rate) translates every row at closing_rate, so its CTA is 0 by construction
-- and must not be flagged (konsolidat#195). Since konsolidat#176 a missing historical
-- equity rate is a warning, not an error, and such equity rows fall back to the
-- closing rate, which makes balance-sheet-only entities with CTA 0 a normal case.
-- Hence the extra `countIf(translation_rate != closing_rate) > 0` condition below.
with rate_check as (
    select
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        max(closing_rate) as max_closing_rate,
        max(average_rate) as max_average_rate
    from {{ ref('gold_consolidated_trial_balance') }}
    where accounting_currency != reporting_currency
    group by consolidation_group, data_area_id, fiscal_year, fiscal_period
    having abs(max(closing_rate) - max(average_rate)) > 0.0001
        -- translation_rate is Nullable: a NULL comparison is not true, so countIf
        -- ignores those rows (a NULL rate is assert_translation_rate_resolved's job)
        and countIf(translation_rate != closing_rate) > 0
)

select
    rc.consolidation_group,
    rc.data_area_id,
    rc.fiscal_year,
    rc.fiscal_period,
    rc.max_closing_rate,
    rc.max_average_rate,
    coalesce(fx.cta_amount, 0) as cta_amount
from rate_check as rc
left join {{ ref('gold_fx_revaluation') }} as fx
    on rc.consolidation_group = fx.consolidation_group
    and rc.data_area_id = fx.data_area_id
    and rc.fiscal_year = fx.fiscal_year
    and rc.fiscal_period = fx.fiscal_period
where coalesce(fx.cta_amount, 0) = 0
