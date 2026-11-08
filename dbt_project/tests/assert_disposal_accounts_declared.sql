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
-- Refused by name (row J12; reworded in the konsol#117 pair 2 review, finding 2): a disposal of a partly owned
-- subsidiary, a partial disposal or a retained interest. Refused when the entity is HELD below 100%
-- (gold_entity_ownership.effective_ownership_pct x 100 at the disposal period, the latest row at or before it)
-- OR share_disposed_pct is below that holding OR retained_interest_pct > 0:
--   disposal of a partly owned subsidiary, a partial disposal or a retained interest is not implemented: the
--   disposal journal derecognises the deal's opening NCI only and recycles the whole CTA (konsolidat#310)
-- Why a full sale of a 70% holding (konsol requires Share Disposed = the current holding, 70) is refused too: the
-- journal would derecognise only the deal journal's NCI, not the attribution layer's (nci_attribution), and would
-- recycle 100% of the CTA where IAS 21.48B recycles only the parent's share. The old test compared share_disposed_pct
-- with 100 and so refused that sale under a misleading reason, and let share 100 against a 70% holding through.
-- Also refused by name (konsol#117 pair 3, row K3): a disposal of an interest in a joint operation, i.e. the entity's
-- latest gold_entity_ownership row at or before the disposal period has consolidation_method 'proportional'. One more
-- row, field consolidation_method (so a joint operation held below 100% shows both rows):
--   disposal of an interest in a joint operation (consolidation_method proportional) is not implemented: end the Ownership Period instead
-- Fixture: .joint_operation.must_flag (expects 2 rows, the holding row and this one).
-- An entity with no ownership row at all is taken as held at 100%. One row per such disposal, whatever the root row
-- declares. Fixtures: .partial_share, .partly_owned, .held_below_100 (.must_flag).
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

-- the entity's holding at the disposal period: the latest gold_entity_ownership row at or before it, in percent
deal_holding as (
    select
        bd.name as deal,
        argMax(eo.effective_ownership_pct, toUInt32(eo.fiscal_year) * 1000 + eo.fiscal_period) * 100.0 as holding_pct,
        argMax(eo.consolidation_method, toUInt32(eo.fiscal_year) * 1000 + eo.fiscal_period) as holding_method
    from {{ source('epm_staging', 'business_disposals') }} as bd
    cross join {{ source('epm_staging', 'fiscal_periods') }} as fp
    inner join {{ ref('gold_entity_ownership') }} as eo
        on eo.consolidation_group = bd.consolidation_group
        and eo.data_area_id = bd.disposed_entity
    where fp.start_date <= bd.disposal_date
      and fp.end_date >= bd.disposal_date
      and fp.period_type != 'Closing'
      and toUInt32(eo.fiscal_year) * 1000 + eo.fiscal_period <= toUInt32(fp.fiscal_year) * 1000 + fp.fiscal_period
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
        toUInt64(coalesce(dp.n_periods, 0)) as n_periods,
        -- no ownership row: taken as held at 100%, so a share below 100 is still refused
        if(dh.deal = '', 100.0, dh.holding_pct) as holding_pct,
        toUInt8(dh.holding_method = 'proportional') as is_joint_operation
    from {{ source('epm_staging', 'business_disposals') }} as bd
    left join deal_period as dp
        on dp.deal = bd.name
    left join deal_holding as dh
        on dh.deal = bd.name
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
        toUInt8(d.holding_pct < 100.0 - 0.000001
                or d.share_disposed_pct < d.holding_pct - 0.000001
                or d.retained_interest_pct > 0.0) as is_refused,
        d.holding_pct as holding_pct,
        d.is_joint_operation as is_joint_operation,
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
         'share_disposed_pct', 'consolidation_method'] as field,
        [if(has_root = 1, 'declared', ''), if(n_periods > 0, 'declared', ''),
         disposal_gain_loss_account, disposal_proceeds_account,
         goodwill_account, fair_value_adjustment_account, nci_account,
         concat(toString(share_disposed_pct), ' disposed of a holding of ', toString(round(holding_pct, 4)), ', ', toString(retained_interest_pct), ' retained'),
         if(is_joint_operation = 1, 'proportional', 'not proportional')] as value,
        [toUInt8(1), toUInt8(1),
         has_root, has_root,
         has_root, has_root,
         toUInt8(has_root = 1 and is_refused = 1),
         is_refused,
         is_joint_operation] as required,
        [0, 0,
         1, 1,
         1, 1, 1,
         0, 0] as is_account,
        -- the partly-owned / partial-disposal refusal (row J12): the value is present, the disposal is still refused
        [0, 0,
         0, 0,
         0, 0, 0,
         1, 1] as is_refusal
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
            c.is_refusal = 1 and c.field = 'consolidation_method', 'disposal of an interest in a joint operation (consolidation_method proportional) is not implemented: end the Ownership Period instead',
            c.is_refusal = 1, 'disposal of a partly owned subsidiary, a partial disposal or a retained interest is not implemented: the disposal journal derecognises the deal''s opening NCI only and recycles the whole CTA (konsolidat#310)',
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
