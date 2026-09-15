-- konsolidat#198 (design §6): every consolidation journal the warehouse posts from the deal
-- documents sums to zero in its period. A journal is balanced by construction (design §4-5:
-- the last line is the counterpart of all the others), so a row here is a model bug, not a
-- data problem: one-sided rows were exactly what made assert_end_to_end_bs_balances (PRD-22)
-- fail on every acquisition period before this.
--
-- Written against a UNION of the journal models: gold_business_combination_journal (acquisitions,
-- ACQ-…, row J2), gold_goodwill_amortisation_journal (GWA-…, row J5) and
-- gold_business_disposal_journal (disposals, DSP-…, row J6). Fixtures:
-- dbt_project/test_fixtures/business_combination_100pct.sql, goodwill_amortisation.sql,
-- business_disposal.sql.
with journals as (
    select
        journal_id,
        consolidation_group,
        fiscal_year,
        fiscal_period,
        adjustment_amount
    from {{ ref('gold_business_combination_journal') }}

    union all

    select
        journal_id,
        consolidation_group,
        fiscal_year,
        fiscal_period,
        adjustment_amount
    from {{ ref('gold_goodwill_amortisation_journal') }}

    union all

    select
        journal_id,
        consolidation_group,
        fiscal_year,
        fiscal_period,
        adjustment_amount
    from {{ ref('gold_business_disposal_journal') }}
)

select
    journal_id,
    consolidation_group,
    fiscal_year,
    fiscal_period,
    count() as journal_lines,
    sum(adjustment_amount) as net_amount
from journals
group by journal_id, consolidation_group, fiscal_year, fiscal_period
having abs(sum(adjustment_amount)) > 0.01
