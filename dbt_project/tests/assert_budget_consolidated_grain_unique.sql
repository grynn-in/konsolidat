-- konsol#348 S4 (W8; S4-Q3 a): gold_fully_consolidated_budget holds exactly one row per
-- (consolidation_group, data_area_id, scenario_id, cycle, layer, fiscal_year, fiscal_period,
-- main_account, adjustment_type, the budget dimension columns). That is the grain a reader
-- windows or sums over (S5's YTD running total, the budget side of a variance), as
-- gold_consolidated_ytd's ROWS window does over gold_fully_consolidated_tb
-- (assert_journal_grain_unique): a second row on one key is a second running total, not a
-- larger one. The model's three layers are each grouped or keyed to this grain: 'entity' by
-- GROUP BY, 'cta' one plug per (group, entity, period, scenario, cycle, layer), 'nci_attribution'
-- three lines on three accounts of one journal. A row here means a layer passes rows through
-- unsummed, or a grain column (scenario_id, cycle, layer) was dropped from one layer's key so two
-- consolidations landed on one key. journal_id is not part of the grain; the journals seen are
-- reported for the reader.
-- Fixture: test_fixtures/assert_budget_consolidated_grain_unique.must_flag.sql (one duplicated
-- 'entity' key, flagged; the same account under another layer or another adjustment_type, not).
{{ config(severity='error') }}

select
    consolidation_group,
    data_area_id,
    scenario_id,
    cycle,
    layer,
    fiscal_year,
    fiscal_period,
    main_account,
    adjustment_type,
    {{ dim_select(dims=get_budget_dimensions(), trailing=true) }}
    groupUniqArray(journal_id) as journal_ids,
    count() as n_rows,
    sum(amount) as net_amount
from {{ ref('gold_fully_consolidated_budget') }}
group by
    consolidation_group,
    data_area_id,
    scenario_id,
    cycle,
    layer,
    fiscal_year,
    fiscal_period,
    main_account,
    adjustment_type
    {{- dim_group_by(dims=get_budget_dimensions(), leading=true) }}
having count() > 1
