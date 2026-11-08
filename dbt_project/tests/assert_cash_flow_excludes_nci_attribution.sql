{{ config(severity='error') }}
{#
    konsol#117 pair 2 review, finding 6. The NCI attribution journal (adjustment_type
    'nci_attribution', K2) moves the minority's share of result and CTA between equity lines
    (retained earnings / CTA / the NCI account) and sums to zero. It is a reclassification inside
    equity and no cash moves: it must not appear as a cash-flow line. This test names a cash-flow
    line that exists in gold_consolidated_cash_flow only because of that layer.

    Unit-style, no re-implementation of the classification: take the accounts that have rows in the
    attribution layer and in no other layer of the same group and period, look up the seed line they
    map to (published, non-cash) and flag the cash-flow row for that group, period and line. An
    account the attribution layer shares with other layers is not tested (their rows legitimately
    reach the same line); the fixture maps an account only the attribution layer touches (ZZ3400).
    Fixture: dbt_project/test_fixtures/nci_attribution_journal.sql.
#}
with attribution_only as (
    select consolidation_group, fiscal_year, fiscal_period, main_account
    from {{ ref('gold_fully_consolidated_tb') }}
    where fiscal_period > 0
    group by consolidation_group, fiscal_year, fiscal_period, main_account
    having countIf(adjustment_type = 'nci_attribution') > 0
       and countIf(adjustment_type != 'nci_attribution') = 0
)

select
    a.consolidation_group as consolidation_group,
    a.fiscal_year as fiscal_year,
    a.fiscal_period as fiscal_period,
    a.main_account as main_account,
    cf.cf_category as cf_category,
    cf.cf_line_item as cf_line_item,
    c.cash_flow_amount as cash_flow_amount
from attribution_only as a
inner join {{ source('epm_staging', 'cash_flow_categories') }} as cf
    on cf.main_account = a.main_account
    and cf.status = 'Published'
    and cf.is_cash = 0
inner join {{ ref('gold_consolidated_cash_flow') }} as c
    on c.consolidation_group = a.consolidation_group
    and c.fiscal_year = a.fiscal_year
    and c.fiscal_period = a.fiscal_period
    and c.cf_category = cf.cf_category
    and c.cf_line_item = cf.cf_line_item
where abs(c.cash_flow_amount) > 0.000001
