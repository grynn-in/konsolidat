{{
    config(
        materialized='table',
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# konsolidat#198 (design §5): the disposal journal, posted from the deal
   documents konsol submits (epm_staging.business_disposals and its proceeds
   lines; submit = approval, so every row here is a submitted disposal). One
   journal per full disposal, `journal_id = DSP-<group>-<entity>-
   <disposal_date>`, in group currency, posted once in the disposal period,
   and balanced by construction: the gain or loss is the counterpart of every
   other line. assert_disposal_journal_balances proves it per journal
   and period.

   Replaces gold_disposal_adjustments' disposal_gain_loss and cta_recycling
   rows, which were one-sided P&L amounts on a pseudo-account 'DISPOSAL',
   keyed on the Ownership Period and on a month, and left the disposed
   entity's balances in the group balance sheet (#180). The accounts come
   from the group's root row in epm_gold.consolidation_groups
   (data_area_id = ''), declared in konsol; a disposal whose group has no
   root row, or whose date is outside the declared calendar, posts nothing
   here (row J7's guard names it).

   In scope: the full disposal, retained_interest_pct = 0 (loss of control
   with nothing kept). A disposal that keeps an interest posts NOTHING here:
   the remeasurement of the retained interest is out of scope (design §5,
   §7) and is to be named by a warning test, not posted wrong.

   The lines, from what the group carries for the entity at the disposal
   period-end:
     (0) derecognised   every NON-equity balance-sheet account of the entity
                        at -(its cumulative balance) x 100%, from the entity
                        trial balance (gold_trial_balance: the cumulative
                        signed movements up to and including the disposal
                        period, year-end close rows included), translated at
                        the disposal period's governed Closing rate. Assets
                        are credited out, liabilities debited out: the net of
                        these lines is -(net assets at disposal). The equity
                        accounts are NOT touched: the acquisition journal
                        already eliminated the pre-acquisition equity, and
                        the profits retained since belong to the group and
                        stay in group reserves (IFRS 10.B98). The current
                        year's result up to the disposal stays in the group
                        P&L likewise; it is inside the net assets derecognised
                        here, so it is inside the gain or loss.
     (1) goodwill       Cr goodwill_account by the goodwill the entity's
                        acquisition journal(s) booked in this group, net of
                        the amortisation gold_goodwill_amortisation_journal
                        posted in the periods BEFORE the disposal period
                        (design §1: amortise "until fully amortised or
                        disposal"; row J5b stops the schedule there).
     (2) fva            Cr fair_value_adjustment_account by the fair-value
                        adjustments the acquisition booked (no FVA run-off
                        model exists, so the whole amount remains)
     (3) cta            the group's CTA line (main_account 'CTA', where
                        gold_fully_consolidated_tb carries gold_fx_revaluation)
                        by -(the entity's accumulated CTA in this group up to
                        the disposal period): IAS 21.48 recycling to P&L, the
                        counterpart being inside the gain or loss
     (4) nci            Dr nci_account by the NCI the acquisition journal
                        credited (derecognised)
     (5) proceeds       Dr disposal_proceeds_account, one line per
                        business_disposal_proceeds row translated from its
                        own currency at the disposal period's Closing rate
                        (or the header's total_proceeds, group currency, when
                        the document has no lines); the account the group
                        settles deal cash through (design §1)
     (6) gain_loss      disposal_gain_loss_account (P&L): -(sum of every
                        other line), so a credit is a gain: proceeds - (net
                        assets + goodwill + FVA - NCI) + CTA recycled.

   Not here: the parent's own investment line. The acquisition journal's Cr
   investment_account eliminated the parent's carrying amount against the
   acquired equity; what the parent books in its own ledger on the sale is
   the parent's business, and any difference to this group figure is a
   manual topside (design §7).

   Currency: the derecognised balances are translated from the entity's
   accounting currency (epm_staging.entities) and the proceeds lines from
   their own currency to the group's reporting currency at the disposal
   period's governed Closing rate, the period mapped through
   rate_period_map() like every trial-balance translation. A line already
   in group currency translates at 1. The header's total_proceeds, used when
   the document has no lines, is translated from its proceeds_currency the
   same way. The goodwill, FVA, NCI and CTA figures are already in group
   currency.

   A missing rate stops the disposal, it never zeroes it (row J9, PR #203
   review 3 + 4): the entity's rate and every proceeds line's rate are INNER
   JOINed from the disposal's rate set (disposal_rates), and `disposals`
   keeps only the documents whose every line found one, so an unrated
   disposal posts NOTHING. Before, a LEFT JOIN miss read 0 under
   join_use_nulls = 0: an unrated proceeds currency booked proceeds 0 and a
   false loss, an unrated entity currency derecognised nothing and booked a
   false gain. assert_deal_rate_resolved names the pair (deal, from, to,
   period) before this model runs.

   Periods come from epm_staging.fiscal_periods by start_date <= date <=
   end_date, never from the month: a Closing period (one day inside the last
   Regular period) is skipped, so the disposal lands in the Regular period.
   Balances, journals and CTA are compared by (fiscal_year, fiscal_period)
   tuple, never by date.

   line_no: 0 for every derecognised line, 101 goodwill, 102 fva, 103 cta,
   104 nci, 110 + idx for a proceeds line (110 for the header figure),
   199 gain_loss. #}

{# the submitted disposals in scope: full disposals only (retained_interest_pct
   = 0). Filtered here, on the source alone, so that no multi-join CTE below
   carries a WHERE of its own (the old analyzer's predicate pushdown into a
   rewritten multi-join is what a filtered CTE invites). #}
with full_disposals as (
    select
        name,
        consolidation_group,
        disposed_entity,
        disposal_date,
        proceeds_currency,
        total_proceeds
    from {{ source('epm_staging', 'business_disposals') }}
    where toFloat64(retained_interest_pct) <= 0.0
),

{# the group's root row, aggregated with any() per column so that a
   duplicated root row cannot double every line of the journal (row J10;
   assert_consolidation_group_root_unique names the duplicate) #}
group_policy as (
    select
        consolidation_group,
        any(reporting_currency) as reporting_currency,
        any(goodwill_account) as goodwill_account,
        any(fair_value_adjustment_account) as fair_value_adjustment_account,
        any(nci_account) as nci_account,
        any(disposal_proceeds_account) as disposal_proceeds_account,
        any(disposal_gain_loss_account) as disposal_gain_loss_account
    from {{ source('epm_gold', 'consolidation_groups') }}
    where data_area_id = ''
    group by consolidation_group
),

{# the calendar period holding the disposal date; the lowest-numbered
   non-Closing period whose span holds it. A range condition is not a
   ClickHouse join key, so the calendar is cross-joined and filtered. #}
disposal_period as (
    select
        bd.name as deal,
        argMin(toUInt16(fp.fiscal_year), (toUInt16(fp.fiscal_year), toUInt16(fp.fiscal_period))) as fiscal_year,
        argMin(toUInt16(fp.fiscal_period), (toUInt16(fp.fiscal_year), toUInt16(fp.fiscal_period))) as fiscal_period
    from full_disposals as bd
    cross join {{ source('epm_staging', 'fiscal_periods') }} as fp
    where fp.start_date <= bd.disposal_date
      and fp.end_date >= bd.disposal_date
      and fp.period_type != 'Closing'
    group by bd.name
),

entity_currency as (
    select data_area_id, any(accounting_currency) as accounting_currency
    from {{ source('epm_staging', 'entities') }}
    group by data_area_id
),

{# the disposals in scope with their group's accounts and period, before the
   rate check #}
disposals_all as (
    select
        bd.name as deal,
        bd.consolidation_group as consolidation_group,
        bd.disposed_entity as data_area_id,
        bd.disposal_date as disposal_date,
        toFloat64(bd.total_proceeds) as header_proceeds,
        bd.proceeds_currency as proceeds_currency,
        dp.fiscal_year as fiscal_year,
        dp.fiscal_period as fiscal_period,
        if(rpm.mapped = 1, rpm.rate_year, dp.fiscal_year) as rate_year,
        if(rpm.mapped = 1, rpm.rate_period, dp.fiscal_period) as rate_period,
        ec.accounting_currency as entity_currency,
        gp.reporting_currency as reporting_currency,
        gp.goodwill_account as goodwill_account,
        gp.fair_value_adjustment_account as fair_value_adjustment_account,
        gp.nci_account as nci_account,
        gp.disposal_proceeds_account as proceeds_account,
        gp.disposal_gain_loss_account as gain_loss_account,
        concat('DSP-', bd.consolidation_group, '-', bd.disposed_entity, '-', toString(bd.disposal_date)) as journal_id
    from full_disposals as bd
    inner join group_policy as gp
        on gp.consolidation_group = bd.consolidation_group
    inner join disposal_period as dp
        on dp.deal = bd.name
    left join {{ rate_period_map() }} as rpm
        on rpm.fiscal_year = dp.fiscal_year
        and rpm.fiscal_period = dp.fiscal_period
    left join entity_currency as ec
        on ec.data_area_id = bd.disposed_entity
),

{# the governed Closing rate per (from, to, rate period); the same rows
   gold_consolidated_trial_balance translates at #}
closing_rates as (
    select
        from_currency,
        to_currency,
        toUInt16(fiscal_year) as fiscal_year,
        toUInt16(fiscal_period) as fiscal_period,
        any(toFloat64(rate)) as closing_rate
    from {{ source('epm_staging', 'group_exchange_rates') }}
    where rate_type = 'Closing'
    group by from_currency, to_currency, fiscal_year, fiscal_period
),

proceeds_line_count as (
    select parent as deal, count() as n_lines
    from {{ source('epm_staging', 'business_disposal_proceeds') }}
    group by parent
),

{# a proceeds line whose currency has no governed Closing rate into the
   group's currency for the disposal's rate period (a line already in group
   currency needs none) #}
unrated_proceeds as (
    select d.deal as deal
    from {{ source('epm_staging', 'business_disposal_proceeds') }} as p
    inner join disposals_all as d
        on d.deal = p.parent
    where p.currency != d.reporting_currency
      and (p.currency, d.reporting_currency, d.rate_year, d.rate_period) not in (
          select from_currency, to_currency, fiscal_year, fiscal_period from closing_rates
      )
    group by d.deal
),

{# the disposals that post (row J9): the entity's currency is rated (or is
   the group currency), no proceeds line is unrated, and a document with no
   lines has a rated header currency (or a zero header, which posts no
   proceeds line anyway). Decided here once, by set membership on the rate
   keys, so that the translation joins below cannot miss; everything below
   reads this set, so an unrated disposal has no line at all. The rate sets
   are IN-subqueries, not joins: ClickHouse inlines a WITH subquery at every
   reference, and this CTE is read nine times below, so every join layered
   into it is multiplied by nine. NOT IN / IN rather than a LEFT JOIN null
   test (join_use_nulls = 0). #}
disposals as (
    select
        d.deal as deal,
        d.consolidation_group as consolidation_group,
        d.data_area_id as data_area_id,
        d.disposal_date as disposal_date,
        d.header_proceeds as header_proceeds,
        d.proceeds_currency as proceeds_currency,
        d.fiscal_year as fiscal_year,
        d.fiscal_period as fiscal_period,
        d.rate_year as rate_year,
        d.rate_period as rate_period,
        d.entity_currency as entity_currency,
        d.reporting_currency as reporting_currency,
        d.goodwill_account as goodwill_account,
        d.fair_value_adjustment_account as fair_value_adjustment_account,
        d.nci_account as nci_account,
        d.proceeds_account as proceeds_account,
        d.gain_loss_account as gain_loss_account,
        d.journal_id as journal_id
    from disposals_all as d
    left join proceeds_line_count as lc
        on lc.deal = d.deal
    where (
            d.entity_currency = d.reporting_currency
            or (d.entity_currency, d.reporting_currency, d.rate_year, d.rate_period) in (
                select from_currency, to_currency, fiscal_year, fiscal_period from closing_rates
            )
          )
      and d.deal not in (select deal from unrated_proceeds)
      and (
            coalesce(lc.n_lines, 0) > 0
            or abs(d.header_proceeds) <= 0.005
            or d.proceeds_currency = d.reporting_currency
            or (d.proceeds_currency, d.reporting_currency, d.rate_year, d.rate_period) in (
                select from_currency, to_currency, fiscal_year, fiscal_period from closing_rates
            )
          )
),

{# the rates a posting disposal translates at: the governed Closing rates
   into the group's currency for its rate period, plus 1 for the group
   currency itself (a governed row quoting the group currency against itself
   is left out, so it cannot double a line). Every translation below INNER
   JOINs this set on the line's currency; `disposals` guarantees the hit, and
   the INNER JOIN guarantees that a miss could still never read as 0. #}
disposal_rates as (
    select
        d.deal as deal,
        cr.from_currency as from_currency,
        cr.closing_rate as rate
    from disposals as d
    inner join closing_rates as cr
        on cr.to_currency = d.reporting_currency
        and cr.fiscal_year = d.rate_year
        and cr.fiscal_period = d.rate_period
    where cr.from_currency != d.reporting_currency

    union all

    select
        deal,
        reporting_currency as from_currency,
        1.0 as rate
    from disposals
),

{# each disposal's rate from the entity's currency into the group's #}
disposal_entity_rate as (
    select
        d.deal as deal,
        r.rate as entity_rate
    from disposals as d
    inner join disposal_rates as r
        on r.deal = d.deal
        and r.from_currency = d.entity_currency
),

{# line (5): the proceeds lines, each translated from its own currency #}
proceeds_lines as (
    select
        d.deal as deal,
        p.idx as idx,
        p.component as component,
        toFloat64(p.amount) * r.rate as amount
    from {{ source('epm_staging', 'business_disposal_proceeds') }} as p
    inner join disposals as d
        on d.deal = p.parent
    inner join disposal_rates as r
        on r.deal = d.deal
        and r.from_currency = p.currency
),

{# the header's total_proceeds, stated in proceeds_currency
   (_staging__sources.yml), translated the same way (a zero header posts no
   line). Named apart from the header_proceeds column: ClickHouse reads a
   CTE name inside an expression as a scalar subquery. #}
header_proceeds_rated as (
    select
        d.deal as deal,
        d.header_proceeds * r.rate as amount
    from disposals as d
    inner join disposal_rates as r
        on r.deal = d.deal
        and r.from_currency = d.proceeds_currency
    where abs(d.header_proceeds) > 0.005
),

{# lines (1), (2), (4): what the entity's acquisition journal(s) booked in
   this group up to the disposal period #}
acquired as (
    select
        d.deal as deal,
        sumIf(j.adjustment_amount, j.account_role = 'goodwill') as goodwill,
        sumIf(j.adjustment_amount, j.account_role = 'fva') as fva,
        sumIf(j.adjustment_amount, j.account_role = 'nci') as nci
    from {{ ref('gold_business_combination_journal') }} as j
    inner join disposals as d
        on d.consolidation_group = j.consolidation_group
        and d.data_area_id = j.data_area_id
    where (toUInt16(j.fiscal_year), toUInt16(j.fiscal_period)) <= (d.fiscal_year, d.fiscal_period)
    group by d.deal
),

{# line (1): the amortisation already posted against that goodwill, in the
   periods before the disposal period (negative amounts) #}
amortised as (
    select
        d.deal as deal,
        sum(a.adjustment_amount) as amortised
    from {{ ref('gold_goodwill_amortisation_journal') }} as a
    inner join disposals as d
        on d.consolidation_group = a.consolidation_group
        and d.data_area_id = a.data_area_id
    where a.account_role = 'goodwill'
      and (toUInt16(a.fiscal_year), toUInt16(a.fiscal_period)) < (d.fiscal_year, d.fiscal_period)
    group by d.deal
),

{# line (3): the entity's accumulated CTA in this group up to the disposal
   period #}
accumulated_cta as (
    select
        d.deal as deal,
        sum(fx.cta_amount) as cta
    from {{ ref('gold_fx_revaluation') }} as fx
    inner join disposals as d
        on d.consolidation_group = fx.consolidation_group
        and d.data_area_id = fx.data_area_id
    where (toUInt16(fx.fiscal_year), toUInt16(fx.fiscal_period)) <= (d.fiscal_year, d.fiscal_period)
    group by d.deal
),

{# the chart's equity flag, so the equity accounts are left alone #}
equity_accounts as (
    select main_account_id, max(is_equity) as is_equity
    from {{ ref('silver_main_accounts') }}
    group by main_account_id
),

{# line (0): the entity's non-equity balance-sheet position at the disposal
   period-end, in local currency: the cumulative signed movements up to and
   including that period. A tuple comparison, never a date or month. #}
carried_balances as (
    select
        d.deal as deal,
        tb.main_account as main_account,
        any(tb.account_name) as account_name,
        sum(toFloat64(tb.period_debit) - toFloat64(tb.period_credit)) as local_balance
    from {{ ref('gold_trial_balance') }} as tb
    inner join disposals as d
        on d.data_area_id = tb.data_area_id
    left join equity_accounts as ea
        on ea.main_account_id = tb.main_account
    where tb.is_balance_sheet = 1
      and coalesce(ea.is_equity, 0) = 0
      and (toUInt16(tb.fiscal_year), toUInt16(tb.fiscal_period)) <= (d.fiscal_year, d.fiscal_period)
    group by d.deal, tb.main_account
),

derecognised_lines as (
    select
        d.deal as deal,
        d.consolidation_group as consolidation_group,
        d.data_area_id as data_area_id,
        d.fiscal_year as fiscal_year,
        d.fiscal_period as fiscal_period,
        cb.main_account as main_account,
        cb.account_name as account_name,
        -(cb.local_balance * er.entity_rate) as adjustment_amount,
        d.disposal_date as disposal_date,
        d.journal_id as journal_id,
        toUInt16(0) as line_no,
        'derecognised' as account_role
    from carried_balances as cb
    inner join disposals as d
        on d.deal = cb.deal
    inner join disposal_entity_rate as er
        on er.deal = cb.deal
    where abs(cb.local_balance * er.entity_rate) > 0.005
),

{# one row per disposal with every fixed figure, joined BEFORE the ARRAY
   JOIN: ClickHouse reads ARRAY JOIN before JOIN and cannot fan out over
   joined columns. A figure with no rows to sum joins nothing (0 under
   join_use_nulls = 0, NULL otherwise), hence the coalesce. #}
figures as (
    select
        d.deal as deal,
        d.consolidation_group as consolidation_group,
        d.data_area_id as data_area_id,
        d.fiscal_year as fiscal_year,
        d.fiscal_period as fiscal_period,
        d.disposal_date as disposal_date,
        d.journal_id as journal_id,
        d.goodwill_account as goodwill_account,
        d.fair_value_adjustment_account as fair_value_adjustment_account,
        d.nci_account as nci_account,
        coalesce(a.goodwill, 0.0) + coalesce(am.amortised, 0.0) as goodwill_remaining,
        coalesce(a.fva, 0.0) as fva,
        coalesce(a.nci, 0.0) as nci,
        coalesce(c.cta, 0.0) as cta
    from disposals as d
    left join acquired as a
        on a.deal = d.deal
    left join amortised as am
        on am.deal = d.deal
    left join accumulated_cta as c
        on c.deal = d.deal
),

fixed_raw as (
    select
        deal,
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        disposal_date,
        journal_id,
        line_account,
        line_amount,
        line_no,
        account_role,
        default_name
    from figures
    array join
        [goodwill_account, fair_value_adjustment_account, 'CTA', nci_account] as line_account,
        [-goodwill_remaining, -fva, -cta, -nci] as line_amount,
        [toUInt16(101), toUInt16(102), toUInt16(103), toUInt16(104)] as line_no,
        ['goodwill', 'fva', 'cta', 'nci'] as account_role,
        ['Goodwill derecognised on disposal', 'Fair value adjustments derecognised on disposal', 'CTA recycled on disposal', 'Non-controlling interest derecognised on disposal'] as default_name
    where abs(line_amount) > 0.005
),

{# line (5): one line per proceeds row, or the header figure when the
   document has none #}
proceeds_raw as (
    select
        d.deal as deal,
        d.consolidation_group as consolidation_group,
        d.data_area_id as data_area_id,
        d.fiscal_year as fiscal_year,
        d.fiscal_period as fiscal_period,
        d.disposal_date as disposal_date,
        d.journal_id as journal_id,
        d.proceeds_account as line_account,
        pl.amount as line_amount,
        toUInt16(110 + pl.idx) as line_no,
        'proceeds' as account_role,
        concat('Disposal proceeds: ', pl.component) as default_name
    from proceeds_lines as pl
    inner join disposals as d
        on d.deal = pl.deal
    where abs(pl.amount) > 0.005

    union all

    select
        d.deal as deal,
        d.consolidation_group as consolidation_group,
        d.data_area_id as data_area_id,
        d.fiscal_year as fiscal_year,
        d.fiscal_period as fiscal_period,
        d.disposal_date as disposal_date,
        d.journal_id as journal_id,
        d.proceeds_account as line_account,
        hp.amount as line_amount,
        toUInt16(110) as line_no,
        'proceeds' as account_role,
        'Disposal proceeds' as default_name
    from disposals as d
    inner join header_proceeds_rated as hp
        on hp.deal = d.deal
    left join proceeds_line_count as pc
        on pc.deal = d.deal
    where coalesce(pc.n_lines, 0) = 0
      and abs(hp.amount) > 0.005
),

{# chart names for the declared accounts; the default name when the chart
   lacks the code #}
chart as (
    select main_account_id, any(account_name) as account_name
    from {{ ref('silver_main_accounts') }}
    group by main_account_id
),

fixed_and_proceeds_raw as (
    select * from fixed_raw
    union all
    select * from proceeds_raw
),

fixed_lines as (
    select
        l.deal as deal,
        l.consolidation_group as consolidation_group,
        l.data_area_id as data_area_id,
        l.fiscal_year as fiscal_year,
        l.fiscal_period as fiscal_period,
        l.line_account as main_account,
        if(ch.account_name != '', ch.account_name, l.default_name) as account_name,
        l.line_amount as adjustment_amount,
        l.disposal_date as disposal_date,
        l.journal_id as journal_id,
        l.line_no as line_no,
        l.account_role as account_role
    from fixed_and_proceeds_raw as l
    left join chart as ch
        on ch.main_account_id = l.line_account
),

other_lines as (
    select * from derecognised_lines
    union all
    select * from fixed_lines
),

{# line (6): the counterpart of everything else. Its own alias, so no HAVING
   or WHERE re-expands an aggregate. #}
balancing as (
    select
        deal,
        -sum(adjustment_amount) as balancing_amount
    from other_lines
    group by deal
),

gain_loss_lines as (
    select
        d.deal as deal,
        d.consolidation_group as consolidation_group,
        d.data_area_id as data_area_id,
        d.fiscal_year as fiscal_year,
        d.fiscal_period as fiscal_period,
        d.gain_loss_account as main_account,
        if(ch.account_name != '', ch.account_name, 'Gain or loss on disposal') as account_name,
        b.balancing_amount as adjustment_amount,
        d.disposal_date as disposal_date,
        d.journal_id as journal_id,
        toUInt16(199) as line_no,
        'gain_loss' as account_role
    from balancing as b
    inner join disposals as d
        on d.deal = b.deal
    left join chart as ch
        on ch.main_account_id = d.gain_loss_account
    where abs(b.balancing_amount) > 0.005
),

journal as (
    select * from other_lines
    union all
    select * from gain_loss_lines
)

select
    consolidation_group,
    data_area_id,
    fiscal_year,
    toUInt8(fiscal_period) as fiscal_period,
    main_account,
    account_name,
    'disposal' as adjustment_type,
    adjustment_amount,
    disposal_date,
    journal_id,
    line_no,
    account_role,
    deal
from journal
