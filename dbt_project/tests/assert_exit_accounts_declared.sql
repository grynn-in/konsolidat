-- konsolidat#335, option A (decided 14 Nov 2026 by Deepak Pai), task X2: an ownership exit whose group root has
-- not declared the accounts the exit journal (gold_ownership_exit_journal, tasks X3-X5) will post to. dbt never
-- assumes an account code (design §1), so an undeclared account would post to main_account '' or be dropped;
-- this test stops the build and names it. One row per exit event and field: group, entity, exit period, field,
-- the value found, and why it is not acceptable. It mirrors assert_disposal_accounts_declared, whose rule it reuses.
-- Fixtures: test_fixtures/assert_exit_accounts_declared.must_flag.sql (expects 4 rows) and .declared.sql (passes).
--
-- Exit events come from macros/ownership_exits() (X1): E live in G the previous declared period, not live in P,
-- not ended by its own full Business Disposal. SCOPE: every exit event requires the account. The test is NOT
-- restricted to exits with carried balances: that would read the exit journal, which is not built yet
-- (X3); once it is, narrowing is a follow-up.
--
-- What is required:
--   root_row                  the group's root row in epm_gold.consolidation_groups (data_area_id = ''), read with
--                             any() per column as gold_business_disposal_journal reads it; without it nothing else
--                             of the group is checked
--   exit_gain_loss_account    always: the balancing line of every exit journal. May equal the disposal account;
--                             never falls back to it
--   nci_account               when the entity carried NCI: method_before 'full' and share_before below 1
--                             (ownership_exits() carries effective_ownership_pct, 0..1)
-- A declared account must be a Published posting leaf of the chart: the same rule as
-- assert_disposal_accounts_declared, membership in silver_main_accounts (status 'Published', is_group = 0,
-- main_account_id != '').
with root as (
    select
        consolidation_group,
        count() as n_root,
        any(exit_gain_loss_account) as exit_gain_loss_account,
        any(nci_account) as nci_account
    from {{ source('epm_gold', 'consolidation_groups') }}
    where data_area_id = ''
    group by consolidation_group
),

chart as (
    select main_account_id
    from {{ ref('silver_main_accounts') }}
    where main_account_id != ''
    group by main_account_id
),

exits as (
    select
        x.consolidation_group as consolidation_group,
        x.data_area_id as data_area_id,
        x.fiscal_year as fiscal_year,
        x.fiscal_period as fiscal_period,
        toUInt8(x.method_before = 'full' and x.share_before < 1.0 - 0.000001) as carried_nci,
        toUInt8(coalesce(r.n_root, 0) > 0) as has_root,
        coalesce(r.exit_gain_loss_account, '') as exit_gain_loss_account,
        coalesce(r.nci_account, '') as nci_account
    from {{ ownership_exits() }} as x
    left join root as r
        on r.consolidation_group = x.consolidation_group
),

checks as (
    select
        consolidation_group, data_area_id, fiscal_year, fiscal_period,
        field, value, required, is_account
    from exits
    array join
        ['root_row', 'exit_gain_loss_account', 'nci_account'] as field,
        [if(has_root = 1, 'declared', ''), exit_gain_loss_account, nci_account] as value,
        [toUInt8(1), has_root, toUInt8(has_root = 1 and carried_nci = 1)] as required,
        [0, 1, 1] as is_account
),

judged as (
    select
        c.consolidation_group as consolidation_group,
        c.data_area_id as data_area_id,
        c.fiscal_year as fiscal_year,
        c.fiscal_period as fiscal_period,
        c.field as field,
        c.value as declared_value,
        multiIf(
            c.required = 0, '',
            c.value = '', 'missing',
            c.is_account = 1 and coalesce(ch.main_account_id, '') = '', 'not a posting account of the chart',
            ''
        ) as reason
    from checks as c
    left join chart as ch
        on ch.main_account_id = c.value
)

select
    consolidation_group,
    data_area_id as exited_entity,
    fiscal_year,
    fiscal_period,
    field,
    declared_value,
    reason
from judged
where reason != ''
order by consolidation_group, exited_entity, fiscal_year, fiscal_period, field
