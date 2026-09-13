-- konsolidat#93 / konsol#103: every key gold_consolidated_trial_balance
-- translates (unscoped) that has no usable governed rate, with the reason:
--   missing   no approved Closing AND Average rate in epm_staging.group_exchange_rates
--   duplicate more than one approved rate of one type
--   invalid   a rate that is zero, negative or not a finite number
-- Zero rows = every translated foreign-currency key can be translated. The
-- model's pre_hook guard refuses the build on the same keys (it also refuses a
-- rate more than 10x from the usd_log10 references, which needs that column
-- and is left out here). Used by deploy.sh before step 5, and to prove konsol's
-- rate adoption. Standalone (no Jinja):
--   clickhouse-client --query "$(cat scripts/sql/fx_governed_rate_gaps.sql)"
-- KEEP IN STEP with dbt_project/macros/governed_rates.sql governed_rate_gaps()
-- and scripts/sql/fx_translated_keys.sql.
WITH translated AS (
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
),
governed AS (
    SELECT
        from_currency AS g_from,
        to_currency AS g_to,
        toUInt16(fiscal_year) AS g_fy,
        toUInt16(fiscal_period) AS g_fp,
        countIf(rate_type = 'Closing') AS n_closing,
        countIf(rate_type = 'Average') AS n_average,
        countIf(NOT (isFinite(rate) AND rate > 0)) AS n_invalid
    FROM epm_staging.group_exchange_rates
    GROUP BY from_currency, to_currency, fiscal_year, fiscal_period
)
SELECT
    from_currency,
    to_currency,
    fy AS fiscal_year,
    fp AS fiscal_period,
    multiIf(
        (from_currency, to_currency, fy, fp) NOT IN (
            SELECT g_from, g_to, g_fy, g_fp FROM governed WHERE n_closing > 0 AND n_average > 0), 'missing',
        (from_currency, to_currency, fy, fp) IN (
            SELECT g_from, g_to, g_fy, g_fp FROM governed WHERE n_closing > 1 OR n_average > 1), 'duplicate',
        (from_currency, to_currency, fy, fp) IN (
            SELECT g_from, g_to, g_fy, g_fp FROM governed WHERE n_invalid > 0), 'invalid',
        ''
    ) AS problem
FROM translated
WHERE problem != ''
ORDER BY from_currency, to_currency, fiscal_year, fiscal_period
