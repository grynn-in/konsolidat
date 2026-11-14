-- konsolidat#316 (#357 review F5): the journal close posts no line for an account whose year P&L nets to 0.
-- A zero line is noise in the TB and in the audit trail; the retained-earnings line is the minus sum of the
-- lines kept, so dropping zero lines leaves every journal_close journal balanced.
select
    consolidation_group,
    fiscal_year,
    main_account,
    sum(amount) as line_amount
from {{ ref('gold_fully_consolidated_tb') }}
where adjustment_type = 'journal_close'
group by consolidation_group, data_area_id, fiscal_year, main_account{{ dim_group_by(leading=true) }}
having abs(sum(amount)) < 0.005
