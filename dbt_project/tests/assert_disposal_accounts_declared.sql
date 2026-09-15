-- konsolidat#198 (design §1/§5, row J10; PR #203 review 2): a submitted Business Disposal whose group has not
-- declared an account the disposal journal posts to. gold_business_disposal_journal never assumes an account
-- code (design §1: "dbt never assumes a code"), so an undeclared account either drops the disposal (no root
-- row, no calendar period) or posts to main_account ''. Both are silent; this test stops the build and names
-- them: one row per disposal and field, with the value found and why it is not acceptable. It mirrors
-- assert_acquisition_accounts_declared for the acquisition journal.
-- Fixture: dbt_project/test_fixtures/assert_disposal_accounts_declared.must_flag.sql.
--
-- What is required, and when (design §1 "Required when"; §1a "there are no defaults"):
--   root_row                       the group's root row in epm_gold.consolidation_groups (data_area_id = ''),
--                                  where konsol syncs the accounts; without it nothing else of the group is
--                                  checked (one line says it all)
--   disposal_period                a non-Closing epm_staging.fiscal_periods row spanning disposal_date
--   disposal_gain_loss_account     always: the balancing line of every disposal journal
--   disposal_proceeds_account      always: the proceeds debit (the account the group settles deal cash through)
--   goodwill_account               always: the goodwill the acquisition booked is derecognised here (a deal
--   fair_value_adjustment_account  with none posts a zero, but the account must still be known)
--   nci_account                    when a minority exists: retained_interest_pct > 0 or share_disposed_pct < 100
-- A declared account must also be a Published posting leaf of the chart (silver_main_accounts): the journal
-- would otherwise post to a code the chart does not know.
--
-- Refused by name until konsolidat#204 is decided (row J12, PR #203 review 1):
--   share_disposed_pct < 100 or retained_interest_pct > 0
--                                  layer 1 of gold_fully_consolidated_tb carries a full-method subsidiary at the
--                                  parent's share, while the disposal template derecognises 100% of the balance
--                                  sheet against an NCI line, so a partial disposal (or one leaving a retained
--                                  interest) would count the minority twice. One row per such disposal, whatever
--                                  the root row declares; the disposal journal posts nothing for it either
--                                  (design §5/§7), which assert_disposal_gain_loss_exists also names.
--
-- Not checked here: the acquisition journal's accounts and policies are assert_acquisition_accounts_declared's.
with root as (
    select
        consolidation_group,
        count() as n_root,
        any(goodwill_account) as goodwill_account,
        any(fair_value_adjustment_account) as fair_value_adjustment_account,
        any(nci_account) as nci_account,
        any(disposal_proceeds_account) as disposal_proceeds_account,
        any(disposal_gain_loss_account) as disposal_gain_loss_account
    from {{ source('epm_gold', 'consolidation_groups') }}
    where data_area_id = ''
    group by consolidation_group
),

-- the calendar period holding the disposal date, as the journal finds it (span, never month)
deal_period as (
    select
        bd.name as deal,
        count() as n_periods
    from {{ source('epm_staging', 'business_disposals') }} as bd
    cross join {{ source('epm_staging', 'fiscal_periods') }} as fp
    where fp.start_date <= bd.disposal_date
      and fp.end_date >= bd.disposal_date
      and fp.period_type != 'Closing'
    group by bd.name
),

deals_base as (
    select
        bd.name as deal,
        bd.consolidation_group as consolidation_group,
        bd.disposed_entity as disposed_entity,
        bd.disposal_date as disposal_date,
        toFloat64(bd.share_disposed_pct) as share_disposed_pct,
        toFloat64(bd.retained_interest_pct) as retained_interest_pct,
        toUInt64(coalesce(dp.n_periods, 0)) as n_periods
    from {{ source('epm_staging', 'business_disposals') }} as bd
    left join deal_period as dp
        on dp.deal = bd.name
),

chart as (
    select main_account_id
    from {{ ref('silver_main_accounts') }}
    where main_account_id != ''
    group by main_account_id
),

-- one row per disposal with everything the checks read; a join miss reads '' / 0 under either join_use_nulls
deals as (
    select
        d.deal as deal,
        d.consolidation_group as consolidation_group,
        d.disposed_entity as disposed_entity,
        d.disposal_date as disposal_date,
        d.share_disposed_pct as share_disposed_pct,
        d.retained_interest_pct as retained_interest_pct,
        d.n_periods as n_periods,
        toUInt8(coalesce(r.n_root, 0) > 0) as has_root,
        coalesce(r.goodwill_account, '') as goodwill_account,
        coalesce(r.fair_value_adjustment_account, '') as fair_value_adjustment_account,
        coalesce(r.nci_account, '') as nci_account,
        coalesce(r.disposal_proceeds_account, '') as disposal_proceeds_account,
        coalesce(r.disposal_gain_loss_account, '') as disposal_gain_loss_account
    from deals_base as d
    left join root as r
        on r.consolidation_group = d.consolidation_group
),

-- one row per disposal and field: what is declared and whether the disposal needs it
checks as (
    select
        deal,
        consolidation_group,
        disposed_entity,
        disposal_date,
        field,
        value,
        required,
        is_account,
        is_refusal
    from deals
    array join
        ['root_row', 'disposal_period',
         'disposal_gain_loss_account', 'disposal_proceeds_account',
         'goodwill_account', 'fair_value_adjustment_account', 'nci_account',
         'share_disposed_pct'] as field,
        [if(has_root = 1, 'declared', ''), if(n_periods > 0, 'declared', ''),
         disposal_gain_loss_account, disposal_proceeds_account,
         goodwill_account, fair_value_adjustment_account, nci_account,
         concat(toString(share_disposed_pct), ' disposed, ', toString(retained_interest_pct), ' retained')] as value,
        [toUInt8(1), toUInt8(1),
         has_root, has_root,
         has_root, has_root,
         toUInt8(has_root = 1 and (retained_interest_pct > 0.0 or share_disposed_pct < 100.0)),
         toUInt8(retained_interest_pct > 0.0 or share_disposed_pct < 100.0)] as required,
        [0, 0,
         1, 1,
         1, 1, 1,
         0] as is_account,
        -- the partial-share refusal (row J12): the value is present, the disposal is still refused
        [0, 0,
         0, 0,
         0, 0, 0,
         1] as is_refusal
),

judged as (
    select
        c.deal as deal,
        c.consolidation_group as consolidation_group,
        c.disposed_entity as disposed_entity,
        c.disposal_date as disposal_date,
        c.field as field,
        c.value as declared_value,
        multiIf(
            c.required = 0, '',
            c.is_refusal = 1, 'partial-share deals wait for konsolidat#204: layer 1 carries the entity at its share',
            c.value = '', 'missing',
            c.is_account = 1 and coalesce(ch.main_account_id, '') = '', 'not a posting account of the chart',
            ''
        ) as reason
    from checks as c
    left join chart as ch
        on ch.main_account_id = c.value
)

select
    deal as business_disposal,
    consolidation_group,
    disposed_entity,
    disposal_date,
    field,
    declared_value,
    reason
from judged
where reason != ''
order by business_disposal, field
