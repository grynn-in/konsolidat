-- konsolidat#93: the (from-currency, group reporting currency, fiscal year,
-- fiscal period) keys gold_consolidated_trial_balance translates, with the
-- model's own filters: resolved entity currencies, a complete ownership chain,
-- line consolidation (not equity / none), the group's currency from its node.
-- Standalone (no Jinja): clickhouse-client --query "$(cat scripts/sql/fx_translated_keys.sql)"
-- KEEP IN STEP with dbt_project/macros/governed_rates.sql governed_rate_gaps().
SELECT DISTINCT
    ec.accounting_currency AS from_currency,
    grp.reporting_currency AS to_currency,
    toUInt16(tb.fiscal_year) AS fy,
    toUInt16(tb.fiscal_period) AS fp
FROM epm_gold.gold_trial_balance AS tb
INNER JOIN (
    SELECT data_area_id, accounting_currency
    FROM epm_silver.silver_entity_currencies
    WHERE accounting_currency != ''
) AS ec ON ec.data_area_id = tb.data_area_id
INNER JOIN epm_gold.gold_entity_ownership AS eo
    ON eo.data_area_id = tb.data_area_id
    AND eo.fiscal_year = tb.fiscal_year
    AND eo.fiscal_period = tb.fiscal_period
LEFT JOIN (
    SELECT consolidation_group, reporting_currency
    FROM epm_gold.consolidation_groups
    WHERE data_area_id = ''
) AS grp ON grp.consolidation_group = eo.consolidation_group
WHERE eo.consolidation_method NOT IN ('equity', 'none')
  AND eo.has_complete_chain = 1
  AND ec.accounting_currency != grp.reporting_currency
