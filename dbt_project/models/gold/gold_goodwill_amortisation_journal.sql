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
   per year instalments), or at the end of the declared calendar: a period not
   yet declared posts when it is. Under 'Impairment only' (or any other
   value: row J7's guard names an undeclared policy) the model is empty. A
   deal that booked no goodwill (a bargain purchase, or goodwill 0) has no
   schedule.

   Not yet here: the schedule does not stop at a disposal (design §1: "until
   fully amortised or disposal"). That needs epm_staging.business_disposals,
   which every acquisition fixture would then have to create; row J5b adds it
   once row J6's disposal journal exists, and the disposal journal
   derecognises goodwill net of the amortisation posted to date.

   Every journal sums to zero per period by construction (the two lines are
   each other's counterpart); assert_consolidation_journals_balance proves it
   once its union includes this model (row J5b). Layer 6 of
   gold_fully_consolidated_tb reads it, adjustment_type 'goodwill_amortisation'.

   line_no: 1 for the expense line, 2 for the goodwill credit; `instalment`
   (1 .. n_instalments) numbers the period within the schedule. #}

with group_policy as (
    select
        consolidation_group,
        toUInt32(goodwill_amortisation_years) as amortisation_years,
        goodwill_account,
        goodwill_amortisation_expense_account
    from {{ source('epm_gold', 'consolidation_groups') }}
    where data_area_id = ''
      and goodwill_treatment = 'Amortise'
      and goodwill_amortisation_years > 0
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

{# one row per amortised deal: the goodwill, the number of instalments and
   the accounts #}
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
        concat('GWA-', dg.consolidation_group, '-', dg.data_area_id, '-', toString(dg.acquisition_date)) as journal_id
    from deal_goodwill as dg
    inner join group_policy as gp
        on gp.consolidation_group = dg.consolidation_group
    inner join periods_per_year as ppy
        on ppy.fiscal_year = dg.acquisition_year
),

{# every declared Regular period from the acquisition period on, numbered
   within the deal's schedule. A tuple comparison, never a date or month; a
   range condition is not a ClickHouse join key, so the calendar is
   cross-joined and filtered. #}
schedule_periods as (
    select
        s.deal as deal,
        rp.fiscal_year as fiscal_year,
        rp.fiscal_period as fiscal_period,
        row_number() over (partition by s.deal order by rp.fiscal_year, rp.fiscal_period) as instalment
    from schedules as s
    cross join regular_periods as rp
    where (rp.fiscal_year, rp.fiscal_period) >= (s.acquisition_year, s.acquisition_period)
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
