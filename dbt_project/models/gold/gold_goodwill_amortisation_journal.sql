{{
    config(
        materialized='table',
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# konsolidat#198 (design §1, §5): goodwill amortisation per the group's
   policy. When the group's root row in epm_gold.consolidation_groups
   (data_area_id = '') declares goodwill_treatment = 'Amortise' with
   goodwill_amortisation_years > 0, every deal of the group whose acquisition
   journal (gold_business_combination_journal) booked goodwill is amortised
   straight-line: one journal per deal, `journal_id = GWA-<group>-<entity>-
   <acquisition_date>`, in group currency (the goodwill already is), with two
   lines in every Regular period from the acquisition period on:
     (1) amortisation_expense  Dr goodwill_amortisation_expense_account (P&L)
     (2) goodwill              Cr goodwill_account
   by goodwill / (years x periods per year), where periods per year is the
   number of Regular periods the calendar (epm_staging.fiscal_periods)
   declares for the acquisition year (12 on a monthly calendar, 13 on a
   4-4-5 one with 13 Regular periods); Closing periods never carry a line.
   Each instalment is the rounded cumulative share minus the previous one, so
   the instalments sum to the goodwill exactly whatever the division leaves.

   The schedule stops when the goodwill is fully amortised (years x periods
   per year instalments), at the disposal of the entity (design §1: "until
   fully amortised or disposal"), or at the end of the declared calendar: a
   period not yet declared posts when it is. Under 'Impairment only' (or any
   other value: row J7's guard names an undeclared policy) the model is empty.
   A deal that booked no goodwill (a bargain purchase, or goodwill 0) has no
   schedule.

   The disposal stop (row J5b): a submitted Business Disposal
   (epm_staging.business_disposals) for the same group and entity ends the
   schedule BEFORE its disposal period: the last instalment falls in the
   Regular period preceding the one that holds disposal_date (mapped through
   epm_staging.fiscal_periods by start_date <= date <= end_date, never by
   month, as the acquisition date is), and the disposal journal
   (gold_business_disposal_journal) derecognises the goodwill net of the
   amortisation posted to date in the disposal period itself. The earliest
   disposal of the entity in the group counts; a disposal with a retained
   interest stops the schedule too, though nothing derecognises the goodwill
   then (out of scope, design §7; row J6b's assert_disposal_gain_loss_exists
   names it). Fixtures that build this model must CREATE business_disposals
   (konsol's tables do not exist live yet).

   Every journal sums to zero per period by construction (the two lines are
   each other's counterpart); assert_goodwill_amortisation_journal_balances
   proves it per journal and period. Layer 6 of gold_fully_consolidated_tb
   reads it, adjustment_type 'goodwill_amortisation'.

   line_no: 1 for the expense line, 2 for the goodwill credit; `instalment`
   (1 .. n_instalments) numbers the period within the schedule. #}

{# the group's root row, aggregated with any() per column so that a
   duplicated root row cannot double every line of the journal (row J10;
   assert_consolidation_group_root_unique names the duplicate); the
   Amortise policy is read from the aggregate, in HAVING #}
with group_policy as (
    select
        consolidation_group,
        toUInt32(any(goodwill_amortisation_years)) as amortisation_years,
        any(goodwill_account) as goodwill_account,
        any(goodwill_amortisation_expense_account) as goodwill_amortisation_expense_account
    from {{ source('epm_gold', 'consolidation_groups') }}
    where data_area_id = ''
    group by consolidation_group
    having any(goodwill_treatment) = 'Amortise'
       and any(goodwill_amortisation_years) > 0
),

{# the goodwill each deal's acquisition journal booked, and the period it
   was booked in #}
deal_goodwill as (
    select
        deal,
        consolidation_group,
        data_area_id,
        any(acquisition_date) as acquisition_date,
        toUInt16(fiscal_year) as acquisition_year,
        toUInt16(fiscal_period) as acquisition_period,
        sum(adjustment_amount) as goodwill
    from {{ ref('gold_business_combination_journal') }}
    where account_role = 'goodwill'
    group by deal, consolidation_group, data_area_id, fiscal_year, fiscal_period
    having sum(adjustment_amount) > 0.005
),

{# the declared Regular periods, one row each #}
regular_periods as (
    select
        toUInt16(fiscal_year) as fiscal_year,
        toUInt16(fiscal_period) as fiscal_period
    from {{ source('epm_staging', 'fiscal_periods') }}
    where period_type = 'Regular'
    group by fiscal_year, fiscal_period
),

periods_per_year as (
    select fiscal_year, count() as periods_in_year
    from regular_periods
    group by fiscal_year
),

{# the earliest submitted disposal of each entity in each group, as the
   calendar period holding its date: the lowest-numbered non-Closing period
   whose span holds it, exactly as gold_business_disposal_journal maps it.
   The schedule ends before that period. A range condition is not a
   ClickHouse join key, so the calendar is cross-joined and filtered. #}
disposal_stop as (
    select
        bd.consolidation_group as consolidation_group,
        bd.disposed_entity as data_area_id,
        argMin(toUInt16(fp.fiscal_year), (toUInt16(fp.fiscal_year), toUInt16(fp.fiscal_period))) as stop_year,
        argMin(toUInt16(fp.fiscal_period), (toUInt16(fp.fiscal_year), toUInt16(fp.fiscal_period))) as stop_period,
        toUInt8(1) as has_disposal
    from {{ source('epm_staging', 'business_disposals') }} as bd
    cross join {{ source('epm_staging', 'fiscal_periods') }} as fp
    where fp.start_date <= bd.disposal_date
      and fp.end_date >= bd.disposal_date
      and fp.period_type != 'Closing'
    group by bd.consolidation_group, bd.disposed_entity
),

{# one row per amortised deal: the goodwill, the number of instalments, the
   accounts and the disposal stop when there is one (a join miss reads 0
   under either join_use_nulls) #}
schedules as (
    select
        dg.deal as deal,
        dg.consolidation_group as consolidation_group,
        dg.data_area_id as data_area_id,
        dg.acquisition_date as acquisition_date,
        dg.acquisition_year as acquisition_year,
        dg.acquisition_period as acquisition_period,
        dg.goodwill as goodwill,
        toUInt32(gp.amortisation_years * ppy.periods_in_year) as n_instalments,
        gp.goodwill_account as goodwill_account,
        gp.goodwill_amortisation_expense_account as expense_account,
        concat('GWA-', dg.consolidation_group, '-', dg.data_area_id, '-', toString(dg.acquisition_date)) as journal_id,
        coalesce(ds.has_disposal, 0) as has_disposal,
        coalesce(ds.stop_year, 0) as stop_year,
        coalesce(ds.stop_period, 0) as stop_period
    from deal_goodwill as dg
    inner join group_policy as gp
        on gp.consolidation_group = dg.consolidation_group
    inner join periods_per_year as ppy
        on ppy.fiscal_year = dg.acquisition_year
    left join disposal_stop as ds
        on ds.consolidation_group = dg.consolidation_group
        and ds.data_area_id = dg.data_area_id
),

{# every declared Regular period from the acquisition period on and, when the
   entity is disposed of, before the disposal period, numbered within the
   deal's schedule. A tuple comparison, never a date or month; a range
   condition is not a ClickHouse join key, so the calendar is cross-joined and
   filtered. #}
schedule_periods as (
    select
        s.deal as deal,
        rp.fiscal_year as fiscal_year,
        rp.fiscal_period as fiscal_period,
        row_number() over (partition by s.deal order by rp.fiscal_year, rp.fiscal_period) as instalment
    from schedules as s
    cross join regular_periods as rp
    where (rp.fiscal_year, rp.fiscal_period) >= (s.acquisition_year, s.acquisition_period)
      and (s.has_disposal = 0 or (rp.fiscal_year, rp.fiscal_period) < (s.stop_year, s.stop_period))
),

{# the instalment amount: the rounded cumulative share less the previous
   one, so the schedule sums to the goodwill exactly #}
instalments as (
    select
        s.deal as deal,
        s.consolidation_group as consolidation_group,
        s.data_area_id as data_area_id,
        sp.fiscal_year as fiscal_year,
        sp.fiscal_period as fiscal_period,
        s.acquisition_date as acquisition_date,
        s.journal_id as journal_id,
        toUInt32(sp.instalment) as instalment,
        s.n_instalments as n_instalments,
        s.goodwill_account as goodwill_account,
        s.expense_account as expense_account,
        round(s.goodwill * sp.instalment / s.n_instalments, 2)
            - round(s.goodwill * (sp.instalment - 1) / s.n_instalments, 2) as amount
    from schedule_periods as sp
    inner join schedules as s
        on s.deal = sp.deal
    where sp.instalment <= s.n_instalments
),

{# the two lines of each period; a zero instalment (a tiny goodwill spread
   over many periods) is left out #}
lines_raw as (
    select
        deal,
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        acquisition_date,
        journal_id,
        instalment,
        n_instalments,
        line_account,
        line_amount,
        line_no,
        account_role,
        default_name
    from instalments
    array join
        [expense_account, goodwill_account] as line_account,
        [amount, -amount] as line_amount,
        [toUInt16(1), toUInt16(2)] as line_no,
        ['amortisation_expense', 'goodwill'] as account_role,
        ['Goodwill amortisation', 'Goodwill amortised'] as default_name
    where abs(line_amount) > 0.005
),

{# chart names for the declared accounts; the default name when the chart
   lacks the code #}
chart as (
    select main_account_id, any(account_name) as account_name
    from {{ ref('silver_main_accounts') }}
    group by main_account_id
)

select
    l.consolidation_group as consolidation_group,
    l.data_area_id as data_area_id,
    l.fiscal_year as fiscal_year,
    toUInt8(l.fiscal_period) as fiscal_period,
    l.line_account as main_account,
    if(ch.account_name != '', ch.account_name, l.default_name) as account_name,
    'goodwill_amortisation' as adjustment_type,
    l.line_amount as adjustment_amount,
    l.acquisition_date as acquisition_date,
    l.journal_id as journal_id,
    l.line_no as line_no,
    l.account_role as account_role,
    l.deal as deal,
    l.instalment as instalment,
    l.n_instalments as n_instalments
from lines_raw as l
left join chart as ch
    on ch.main_account_id = l.line_account
