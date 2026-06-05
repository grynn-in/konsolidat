{{
    config(
        engine='MergeTree()',
        order_by='(consolidation_group, data_area_id, fiscal_year, fiscal_period)'
    )
}}

-- CTA (Currency Translation Adjustment)
-- Difference between BS at closing rate and BS at historical rate
-- Simplified: calculates per-entity CTA as rounding difference
with entity_totals as (
    select
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        reporting_currency,
        accounting_currency,
        ownership_pct,
        -- Sum of local amounts
        sum(local_amount) as total_local,
        -- Sum of translated amounts
        sum(group_amount) as total_group
    from {{ ref('gold_consolidated_trial_balance') }}
    where is_balance_sheet = 1
    group by
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        reporting_currency,
        accounting_currency,
        ownership_pct
)

select
    consolidation_group,
    data_area_id,
    fiscal_year,
    fiscal_period,
    reporting_currency,
    accounting_currency,
    total_local,
    total_group,
    'CTA' as adjustment_type,
    -- CTA is booked to equity to keep BS balanced after translation
    0 as cta_amount  -- Placeholder: real CTA requires historical vs closing rate comparison
from entity_totals
