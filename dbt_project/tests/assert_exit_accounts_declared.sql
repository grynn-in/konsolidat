-- konsolidat#335, option A (decided 14 Nov 2026 by Deepak Pai), task X2: an ownership exit whose group root has
-- not declared the accounts the exit journal (gold_ownership_exit_journal, tasks X3-X5) will post to. dbt never
-- assumes an account code (design §1), so an undeclared account would post to main_account '' or be dropped;
-- this test stops the build and names it. One row per exit event and field: group, entity, exit period, field,
-- the value found, and why it is not acceptable. It mirrors assert_disposal_accounts_declared, whose rule it reuses.
-- Fixtures: test_fixtures/assert_exit_accounts_declared.must_flag.sql (4 rows), .declared.sql (passes), .zero_balance.sql
-- (passes), .flagged_without_disposal.must_flag.sql (1 row).
--
-- Exit events come from macros/ownership_exits() (X1): E live in G the previous declared period, not live in P,
-- not ended by its own full Business Disposal. The accounts are required only for an exit whose journal posts
-- something (konsolidat#335 review F3): an exit with carried lines in gold_ownership_exit_journal (joined on
-- group, entity, exit period; ref()d so dbt orders it). An exit with no carried balances (e.g. a legacy link
-- ended years ago with no trial balance rows) posts nothing and needs no account.
-- The journal posts NOTHING while the root's exit_gain_loss_account is undeclared (its `!= ''` filter), so its
-- lines cannot be the only evidence: an undeclared account would hide the very exit that needs it. The second
-- evidence is the carried balance itself, read where the journal reads it: gold_consolidated_trial_balance,
-- non-equity balance sheet accounts of (group, entity) summed over the periods before the exit period, any
-- account above the materiality floor, from the period after the previous exit (or full Business Disposal) of the
-- entity in the group up to AND INCLUDING the exit period P: the span the journal reverses (its from_ord bound,
-- #358 re-review F2). Balances that first appear in P count; the evidence read strictly before P let an entity
-- bought and lost with its first balances in P pass with no account declared. (Goodwill, FVA and NCI come from
-- other layers; they exist only with an acquisition, whose balance sheet accounts show here too.)
--
-- What is required:
--   root_row                  the group's root row in epm_gold.consolidation_groups (data_area_id = ''), read with
--                             any() per column as gold_business_disposal_journal reads it; every exit
--   exit_gain_loss_account    when the exit carries balances (journal lines, or CTB balances): the balancing line. May equal the disposal
--                             account; never falls back to it
--   nci_account               when the exit journal carries an NCI line (account_role 'nci')
--   is_disposal               always: a link ending on this exit's end date with is_disposal = 1 but no submitted
--                             full Business Disposal (retained interest 0) is not a Business Disposal in the
--                             warehouse (ownership_resolution ended_by_disposal needs both), so its end posts as
--                             an exit. Reason 'is_disposal_without_business_disposal': fix the data (submit the
--                             disposal, or clear is_disposal)
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

{# the lower bound of what each exit reverses, as gold_ownership_exit_journal computes from_ord: the period after the
   entity's previous exit, and after its latest full Business Disposal before P (ord = FY x 1000 + period; 0 = all
   history, join_use_nulls = 0 reads an absent earlier event as 0) #}
exit_prev as (
    select
        consolidation_group, data_area_id, fiscal_year, fiscal_period,
        lagInFrame(toUInt32(fiscal_year) * 1000 + fiscal_period, 1, toUInt32(0)) over (
            partition by consolidation_group, data_area_id
            order by fiscal_year, fiscal_period
            rows between unbounded preceding and current row
        ) as previous_exit_ord
    from {{ ownership_exits() }}
),

exit_prev_disposal as (
    select
        x.consolidation_group as consolidation_group,
        x.data_area_id as data_area_id,
        x.fiscal_year as fiscal_year,
        x.fiscal_period as fiscal_period,
        max(toUInt32(d.fiscal_year) * 1000 + d.fiscal_period) as disposal_ord
    from {{ ownership_exits() }} as x
    inner join (
        select distinct consolidation_group, data_area_id, fiscal_year, fiscal_period
        from {{ ref('gold_business_disposal_journal') }}
    ) as d
        on d.consolidation_group = x.consolidation_group
        and d.data_area_id = x.data_area_id
    where (toUInt16(d.fiscal_year), toUInt16(d.fiscal_period)) < (x.fiscal_year, x.fiscal_period)
    group by x.consolidation_group, x.data_area_id, x.fiscal_year, x.fiscal_period
),

exit_span as (
    select
        x.consolidation_group as consolidation_group,
        x.data_area_id as data_area_id,
        x.fiscal_year as fiscal_year,
        x.fiscal_period as fiscal_period,
        greatest(if(pe.previous_exit_ord = 0, toUInt32(0), pe.previous_exit_ord + 1),
                 if(pd.disposal_ord = 0, toUInt32(0), pd.disposal_ord + 1)) as from_ord
    from {{ ownership_exits() }} as x
    left join exit_prev as pe
        on pe.consolidation_group = x.consolidation_group and pe.data_area_id = x.data_area_id
        and pe.fiscal_year = x.fiscal_year and pe.fiscal_period = x.fiscal_period
    left join exit_prev_disposal as pd
        on pd.consolidation_group = x.consolidation_group and pd.data_area_id = x.data_area_id
        and pd.fiscal_year = x.fiscal_year and pd.fiscal_period = x.fiscal_period
),

ctb_carried as (
    select
        x.consolidation_group as consolidation_group,
        x.data_area_id as data_area_id,
        toUInt16(x.fiscal_year) as fiscal_year,
        toUInt16(x.fiscal_period) as fiscal_period,
        c.main_account as main_account,
        sum(toFloat64(coalesce(c.group_amount, 0.0))) as amount
    from exit_span as x
    inner join {{ ref('gold_consolidated_trial_balance') }} as c
        on c.consolidation_group = x.consolidation_group and c.data_area_id = x.data_area_id
    inner join (
        select main_account_id
        from {{ ref('silver_main_accounts') }}
        where is_balance_sheet = 1 and is_equity = 0
        group by main_account_id
    ) as a
        on a.main_account_id = c.main_account
    where toUInt32(c.fiscal_year) * 1000 + toUInt32(c.fiscal_period) >= x.from_ord
        and toUInt32(c.fiscal_year) * 1000 + toUInt32(c.fiscal_period)
        <= toUInt32(x.fiscal_year) * 1000 + toUInt32(x.fiscal_period)
    group by x.consolidation_group, x.data_area_id, x.fiscal_year, x.fiscal_period, c.main_account
    having abs(amount) > {{ materiality_floor() }}
),

ctb_flag as (
    select consolidation_group, data_area_id, fiscal_year, fiscal_period, count() as n_accounts
    from ctb_carried
    group by consolidation_group, data_area_id, fiscal_year, fiscal_period
),

carried as (
    select
        consolidation_group,
        data_area_id,
        toUInt16(fiscal_year) as fiscal_year,
        toUInt16(fiscal_period) as fiscal_period,
        count() as n_lines,
        max(account_role = 'nci') as has_nci_line
    from {{ ref('gold_ownership_exit_journal') }}
    where account_role != 'gain_loss'
    group by consolidation_group, data_area_id, fiscal_year, fiscal_period
),

disposal_flagged as (
    select distinct consolidation_group, data_area_id, end_date
    from {{ source('epm_staging', 'ownership_periods') }}
    where is_disposal = 1
),

exits as (
    select
        x.consolidation_group as consolidation_group,
        x.data_area_id as data_area_id,
        x.fiscal_year as fiscal_year,
        x.fiscal_period as fiscal_period,
        toUInt8(coalesce(c.n_lines, 0) > 0 or coalesce(cf.n_accounts, 0) > 0) as has_carried,
        toUInt8(coalesce(c.has_nci_line, 0) = 1) as carried_nci,
        toUInt8(df.data_area_id != '') as flagged_disposal,
        toUInt8(coalesce(r.n_root, 0) > 0) as has_root,
        coalesce(r.exit_gain_loss_account, '') as exit_gain_loss_account,
        coalesce(r.nci_account, '') as nci_account
    from {{ ownership_exits() }} as x
    left join root as r
        on r.consolidation_group = x.consolidation_group
    left join carried as c
        on c.consolidation_group = x.consolidation_group and c.data_area_id = x.data_area_id
        and c.fiscal_year = toUInt16(x.fiscal_year) and c.fiscal_period = toUInt16(x.fiscal_period)
    left join ctb_flag as cf
        on cf.consolidation_group = x.consolidation_group and cf.data_area_id = x.data_area_id
        and cf.fiscal_year = toUInt16(x.fiscal_year) and cf.fiscal_period = toUInt16(x.fiscal_period)
    left join disposal_flagged as df
        on df.consolidation_group = x.consolidation_group and df.data_area_id = x.data_area_id
        and df.end_date = x.end_date
),

checks as (
    select
        consolidation_group, data_area_id, fiscal_year, fiscal_period,
        field, value, required, is_account
    from exits
    array join
        ['root_row', 'exit_gain_loss_account', 'nci_account', 'is_disposal'] as field,
        [if(has_root = 1, 'declared', ''), exit_gain_loss_account, nci_account, ''] as value,
        [toUInt8(1), toUInt8(has_root = 1 and has_carried = 1), toUInt8(has_root = 1 and carried_nci = 1), flagged_disposal] as required,
        [0, 1, 1, 0] as is_account
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
            c.field = 'is_disposal', 'is_disposal_without_business_disposal',
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
