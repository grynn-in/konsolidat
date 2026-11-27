{#
    konsol#117 pair 2 review, finding 6. The NCI attribution journal (adjustment_type
    'nci_attribution', K2) moves the minority's share of result and CTA between equity lines
    (retained earnings / CTA / the NCI account) and sums to zero. It is a reclassification inside
    equity and no cash moves: it must not appear as a cash-flow line. This test names a cash-flow
    line that exists in gold_consolidated_cash_flow only because of that layer.

    Unit-style, no re-implementation of the classification: map every row of the fully
    consolidated TB to its seed line (published, non-cash), keep the lines of a group and period
    that the attribution layer reaches and no other layer does, and flag the cash-flow row for that
    group, period and line. The decision is made per LINE, the grain of gold_consolidated_cash_flow,
    not per account (konsolidat#351): decided per account, a line the NCI account shared with
    share capital and reserves was flagged as a whole, with an amount that was those accounts'
    entity layer and held nothing of the attribution. A line the attribution layer shares with
    other layers is not tested (their rows legitimately reach the same line); an unmapped account
    is not tested either (the model gives it a default line this test does not re-derive).
    Fixtures: dbt_project/test_fixtures/nci_attribution_journal.sql (the NCI account on a line of
    its own), assert_cash_flow_excludes_nci_attribution.shared_line.sql (the NCI account on a line
    it shares with an account that has entity rows: must pass) and
    assert_cash_flow_excludes_nci_attribution.must_flag.sql (the three tables seeded as a model
    that left the layer in would build them: the lone line flags, the shared line does not).
#}
{{ config(severity='error') }}
with mapped as (
    select
        t.consolidation_group as consolidation_group,
        t.fiscal_year as fiscal_year,
        t.fiscal_period as fiscal_period,
        t.main_account as main_account,
        t.adjustment_type as adjustment_type,
        cf.cf_category as cf_category,
        cf.cf_line_item as cf_line_item
    from {{ ref('gold_fully_consolidated_tb') }} as t
    inner join {{ source('epm_staging', 'cash_flow_categories') }} as cf
        on cf.main_account = t.main_account
        and cf.status = 'Published'
        and cf.is_cash = 0
    where t.fiscal_period > 0
),

attribution_only_lines as (
    select
        consolidation_group,
        fiscal_year,
        fiscal_period,
        cf_category,
        cf_line_item,
        arraySort(groupUniqArray(main_account)) as main_accounts
    from mapped
    group by consolidation_group, fiscal_year, fiscal_period, cf_category, cf_line_item
    having countIf(adjustment_type = 'nci_attribution') > 0
       and countIf(adjustment_type != 'nci_attribution') = 0
)

select
    a.consolidation_group as consolidation_group,
    a.fiscal_year as fiscal_year,
    a.fiscal_period as fiscal_period,
    a.cf_category as cf_category,
    a.cf_line_item as cf_line_item,
    a.main_accounts as main_accounts,
    c.cash_flow_amount as cash_flow_amount
from attribution_only_lines as a
inner join {{ ref('gold_consolidated_cash_flow') }} as c
    on c.consolidation_group = a.consolidation_group
    and c.fiscal_year = a.fiscal_year
    and c.fiscal_period = a.fiscal_period
    and c.cf_category = a.cf_category
    and c.cf_line_item = a.cf_line_item
where abs(c.cash_flow_amount) > 0.000001
