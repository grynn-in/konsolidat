-- konsolidat#316 (#357 review F5): the journal close posts no line for an account whose year P&L nets to 0.
-- A zero line is noise in the TB and in the audit trail; the retained-earnings line is the minus sum of the
-- lines kept, so dropping zero lines leaves every journal_close journal balanced.
-- Zero is judged as the close judges it (#357 re-review R2): journals are kept to 4 places (#353), so a line
-- whose amount rounds to 0 at 4 places (Float dust such as 0.1 + 0.2 - 0.3) is a zero line.
select
    consolidation_group,
    fiscal_year,
    main_account,
    sum(amount) as line_amount
from {{ ref('gold_fully_consolidated_tb') }}
where adjustment_type = 'journal_close'
group by consolidation_group, data_area_id, fiscal_year, main_account{{ dim_group_by(leading=true) }}
having round(sum(amount), 4) = 0
