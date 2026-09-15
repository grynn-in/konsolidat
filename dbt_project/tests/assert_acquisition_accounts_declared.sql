-- konsolidat#198 (design §1/§1a, row J7): a submitted Business Combination whose group has not declared
-- something the acquisition journal needs. gold_business_combination_journal never assumes an account code
-- or a policy (design §1: "dbt never assumes a code"), so an undeclared field either drops the deal (no root
-- row, no calendar period) or posts to main_account '' / reads the policy as its fallback. Both are silent;
-- this test stops the build and names them: one row per deal and field, with the value found and why it is
-- not acceptable. Fixture: dbt_project/test_fixtures/assert_acquisition_accounts_declared.must_flag.sql.
--
-- What is required, and when (design §1 "Required when"; §1a "every setting is required once the group has
-- a Business Combination; there are no defaults"):
--   root_row                     the group's root row in epm_gold.consolidation_groups (data_area_id = ''),
--                                where konsol syncs the accounts and the policy; without it nothing else
--                                of the group is checked (one line says it all)
--   acquisition_period           a non-Closing epm_staging.fiscal_periods row spanning acquisition_date
--   accounting_framework         IFRS | US GAAP | Local
--   nci_measurement              partial | full
--   goodwill_treatment           Impairment only | Amortise
--   acquisition_costs_treatment  Expense | Capitalise
--   measurement_period           Off | 12 months
--   bargain_purchase             Recognise gain | Refuse
--                                (a policy must be present AND one of its options: the journal reads any
--                                other value as 'partial' / 'Expense' / 'Recognise gain', the fallback
--                                this test stops)
--   goodwill_amortisation_years > 0 and goodwill_amortisation_expense_account
--                                                when goodwill_treatment = 'Amortise'
--   goodwill_account, investment_account         when total_consideration > 0
--   fair_value_adjustment_account                when the header or an acquired-balance row carries a
--                                                fair-value adjustment
--   nci_account                                  when share_acquired_pct < 100
--   bargain_purchase_gain_account                when konsol's Result shows a bargain (goodwill < 0 or
--                                                bargain_purchase_gain > 0) under 'Recognise gain'
--   disposal_proceeds_account                    when the deal has acquisition costs (the account the group
--                                                settles deal cash through; the journal's settlement side)
--   acquisition_costs_account                    when it has costs and acquisition_costs_treatment = 'Expense'
--   is_retained_earnings                         the chart flags a retained-earnings account
--                                                (silver_main_accounts.is_retained_earnings) when the entity
--                                                has trial-balance rows before the acquisition period: line
--                                                (0)'s balancing line goes there
-- A declared account must also be a Published posting leaf of the chart (silver_main_accounts): the journal
-- would otherwise post to a code the chart does not know.
--
-- Not checked here: konsol's framework constraints (US GAAP -> full NCI, IFRS -> Impairment only, Local ->
-- framework_note) are the document's validate() rules; the warehouse posts what is declared. The disposal
-- accounts belong to the disposal journal (assert_disposal_gain_loss_exists names a disposal that could not
-- post).
with root as (
    select
        consolidation_group,
        count() as n_root,
        any(accounting_framework) as accounting_framework,
        any(nci_measurement) as nci_measurement,
        any(goodwill_treatment) as goodwill_treatment,
        any(goodwill_amortisation_years) as goodwill_amortisation_years,
        any(acquisition_costs_treatment) as acquisition_costs_treatment,
        any(measurement_period) as measurement_period,
        any(bargain_purchase) as bargain_purchase,
        any(goodwill_account) as goodwill_account,
        any(fair_value_adjustment_account) as fair_value_adjustment_account,
        any(investment_account) as investment_account,
        any(nci_account) as nci_account,
        any(bargain_purchase_gain_account) as bargain_purchase_gain_account,
        any(disposal_proceeds_account) as disposal_proceeds_account,
        any(goodwill_amortisation_expense_account) as goodwill_amortisation_expense_account,
        any(acquisition_costs_account) as acquisition_costs_account
    from {{ source('epm_gold', 'consolidation_groups') }}
    where data_area_id = ''
    group by consolidation_group
),

-- the calendar period holding the acquisition date, as the journal finds it (span, never month)
deal_period as (
    select
        bc.name as deal,
        count() as n_periods,
        argMin(toUInt16(fp.fiscal_year), (toUInt16(fp.fiscal_year), toUInt16(fp.fiscal_period))) as fiscal_year,
        argMin(toUInt16(fp.fiscal_period), (toUInt16(fp.fiscal_year), toUInt16(fp.fiscal_period))) as fiscal_period
    from {{ source('epm_staging', 'business_combinations') }} as bc
    cross join {{ source('epm_staging', 'fiscal_periods') }} as fp
    where fp.start_date <= bc.acquisition_date
      and fp.end_date >= bc.acquisition_date
      and fp.period_type != 'Closing'
    group by bc.name
),

balance_fva as (
    select parent, sum(abs(toFloat64(fair_value_adjustment))) as fva_abs
    from {{ source('epm_staging', 'business_combination_acquired_balances') }}
    group by parent
),

costs as (
    select parent, count() as n_costs
    from {{ source('epm_staging', 'business_combination_costs') }}
    group by parent
),

deals_base as (
    select
        bc.name as deal,
        bc.consolidation_group as consolidation_group,
        bc.acquired_entity as acquired_entity,
        bc.acquisition_date as acquisition_date,
        toFloat64(bc.total_consideration) as total_consideration,
        toFloat64(bc.share_acquired_pct) as share_acquired_pct,
        toFloat64(bc.fair_value_adjustments) as header_fva,
        toFloat64(bc.goodwill) as header_goodwill,
        toFloat64(bc.bargain_purchase_gain) as header_bargain_gain,
        toUInt64(coalesce(dp.n_periods, 0)) as n_periods,
        toUInt16(coalesce(dp.fiscal_year, 0)) as fiscal_year,
        toUInt16(coalesce(dp.fiscal_period, 0)) as fiscal_period
    from {{ source('epm_staging', 'business_combinations') }} as bc
    left join deal_period as dp
        on dp.deal = bc.name
),

-- trial-balance rows of the entity before the acquisition period: line (0) will be posted
history as (
    select d.deal as deal, count() as n_rows
    from deals_base as d
    inner join {{ ref('gold_trial_balance') }} as tb
        on tb.data_area_id = d.acquired_entity
    where d.n_periods > 0
      and (toUInt16(tb.fiscal_year), toUInt16(tb.fiscal_period)) < (d.fiscal_year, d.fiscal_period)
    group by d.deal
),

chart as (
    select main_account_id
    from {{ ref('silver_main_accounts') }}
    where main_account_id != ''
    group by main_account_id
),

-- one row per deal with everything the checks read; a join miss reads '' / 0 under either join_use_nulls
deals as (
    select
        d.deal as deal,
        d.consolidation_group as consolidation_group,
        d.acquired_entity as acquired_entity,
        d.acquisition_date as acquisition_date,
        d.total_consideration as total_consideration,
        d.share_acquired_pct as share_acquired_pct,
        d.header_fva as header_fva,
        d.header_goodwill as header_goodwill,
        d.header_bargain_gain as header_bargain_gain,
        d.n_periods as n_periods,
        toUInt8(coalesce(r.n_root, 0) > 0) as has_root,
        coalesce(r.accounting_framework, '') as accounting_framework,
        coalesce(r.nci_measurement, '') as nci_measurement,
        coalesce(r.goodwill_treatment, '') as goodwill_treatment,
        coalesce(r.goodwill_amortisation_years, 0) as goodwill_amortisation_years,
        coalesce(r.acquisition_costs_treatment, '') as acquisition_costs_treatment,
        coalesce(r.measurement_period, '') as measurement_period,
        coalesce(r.bargain_purchase, '') as bargain_purchase,
        coalesce(r.goodwill_account, '') as goodwill_account,
        coalesce(r.fair_value_adjustment_account, '') as fair_value_adjustment_account,
        coalesce(r.investment_account, '') as investment_account,
        coalesce(r.nci_account, '') as nci_account,
        coalesce(r.bargain_purchase_gain_account, '') as bargain_purchase_gain_account,
        coalesce(r.disposal_proceeds_account, '') as disposal_proceeds_account,
        coalesce(r.goodwill_amortisation_expense_account, '') as goodwill_amortisation_expense_account,
        coalesce(r.acquisition_costs_account, '') as acquisition_costs_account,
        coalesce(bf.fva_abs, 0.0) as balance_fva_abs,
        coalesce(c.n_costs, 0) as n_costs,
        coalesce(h.n_rows, 0) as n_history,
        (select anyIf(main_account_id, is_retained_earnings = 1) from {{ ref('silver_main_accounts') }}) as retained_account
    from deals_base as d
    left join root as r
        on r.consolidation_group = d.consolidation_group
    left join balance_fva as bf
        on bf.parent = d.deal
    left join costs as c
        on c.parent = d.deal
    left join history as h
        on h.deal = d.deal
),

-- one row per deal and field: what is declared, whether the deal needs it, the allowed options
checks as (
    select
        deal,
        consolidation_group,
        acquired_entity,
        acquisition_date,
        field,
        value,
        required,
        options,
        is_account
    from deals
    array join
        ['root_row', 'acquisition_period',
         'accounting_framework', 'nci_measurement', 'goodwill_treatment', 'acquisition_costs_treatment',
         'measurement_period', 'bargain_purchase',
         'goodwill_amortisation_years', 'goodwill_amortisation_expense_account',
         'goodwill_account', 'investment_account', 'fair_value_adjustment_account', 'nci_account',
         'bargain_purchase_gain_account', 'disposal_proceeds_account', 'acquisition_costs_account',
         'is_retained_earnings'] as field,
        [if(has_root = 1, 'declared', ''), if(n_periods > 0, 'declared', ''),
         accounting_framework, nci_measurement, goodwill_treatment, acquisition_costs_treatment,
         measurement_period, bargain_purchase,
         if(goodwill_amortisation_years > 0, toString(goodwill_amortisation_years), ''), goodwill_amortisation_expense_account,
         goodwill_account, investment_account, fair_value_adjustment_account, nci_account,
         bargain_purchase_gain_account, disposal_proceeds_account, acquisition_costs_account,
         retained_account] as value,
        [toUInt8(1), toUInt8(1),
         has_root, has_root, has_root, has_root,
         has_root, has_root,
         toUInt8(has_root = 1 and goodwill_treatment = 'Amortise'), toUInt8(has_root = 1 and goodwill_treatment = 'Amortise'),
         toUInt8(has_root = 1 and total_consideration > 0.0), toUInt8(has_root = 1 and total_consideration > 0.0),
         toUInt8(has_root = 1 and (abs(header_fva) > 0.005 or balance_fva_abs > 0.005)),
         toUInt8(has_root = 1 and share_acquired_pct < 100.0),
         toUInt8(has_root = 1 and bargain_purchase = 'Recognise gain' and (header_goodwill < -0.005 or header_bargain_gain > 0.005)),
         toUInt8(has_root = 1 and n_costs > 0),
         toUInt8(has_root = 1 and n_costs > 0 and acquisition_costs_treatment = 'Expense'),
         toUInt8(has_root = 1 and n_history > 0)] as required,
        [emptyArrayString(), emptyArrayString(),
         ['IFRS', 'US GAAP', 'Local'], ['partial', 'full'], ['Impairment only', 'Amortise'], ['Expense', 'Capitalise'],
         ['Off', '12 months'], ['Recognise gain', 'Refuse'],
         emptyArrayString(), emptyArrayString(),
         emptyArrayString(), emptyArrayString(), emptyArrayString(), emptyArrayString(),
         emptyArrayString(), emptyArrayString(), emptyArrayString(),
         emptyArrayString()] as options,
        [0, 0,
         0, 0, 0, 0,
         0, 0,
         0, 1,
         1, 1, 1, 1,
         1, 1, 1,
         1] as is_account
),

judged as (
    select
        c.deal as deal,
        c.consolidation_group as consolidation_group,
        c.acquired_entity as acquired_entity,
        c.acquisition_date as acquisition_date,
        c.field as field,
        c.value as declared_value,
        multiIf(
            c.required = 0, '',
            c.value = '', 'missing',
            length(c.options) > 0 and not has(c.options, c.value), concat('not a declared option: ', arrayStringConcat(c.options, ' | ')),
            c.is_account = 1 and coalesce(ch.main_account_id, '') = '', 'not a posting account of the chart',
            ''
        ) as reason
    from checks as c
    left join chart as ch
        on ch.main_account_id = c.value
)

select
    deal as business_combination,
    consolidation_group,
    acquired_entity,
    acquisition_date,
    field,
    declared_value,
    reason
from judged
where reason != ''
order by business_combination, field
