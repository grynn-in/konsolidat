{{
    config(
        materialized='table',
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# konsolidat#198 (design §4): the acquisition journal, posted from the deal
   documents konsol submits (epm_staging.business_combinations and its child
   tables; submit = approval, so every row here is a submitted deal). One
   journal per deal, `journal_id = ACQ-<group>-<entity>-<acquisition_date>`,
   in group currency, posted once in the acquisition period, and balanced by
   construction: the investment and NCI credits are the counterpart of every
   other line. assert_acquisition_journal_balances proves it per journal
   and period.

   Replaces gold_acquisition_adjustments' goodwill_entries and fva_entries,
   which were one-sided debits to the hardcoded accounts '1800'/'1900' and
   made assert_end_to_end_bs_balances (PRD-22) fail on every acquisition
   period. The accounts and the policy come from the group's root row in
   epm_gold.consolidation_groups (data_area_id = ''), declared in konsol: a
   deal whose group has no root row, or whose date is outside the declared
   calendar, posts nothing here (row J7's assert_acquisition_accounts_declared
   names it).

   The lines, with the acquired-balances table (row J2) and rows J3's
   pre-acquisition history and NCI:
     (0) opening_balance    only when the entity has trial-balance history
                            BEFORE the acquisition period: every balance-sheet
                            account at its balance at the last pre-acquisition
                            period-end (100%, the cumulative movements of
                            gold_trial_balance, year-end close rows included),
                            translated at the acquisition period's closing
                            rate. Its ownership window starts at the
                            acquisition, so gold_consolidated_trial_balance
                            carries only its in-window movements and never its
                            opening position (gold_entity_ownership resolves
                            the earlier periods as outside the window, and the
                            consolidated TB drops them); this line brings the
                            acquired balance sheet into the group from the
                            acquisition period on (design §3). When those
                            balances do not sum to zero (a mid-year position
                            whose current-year result still sits in the P&L
                            accounts), one more opening_balance line books the
                            difference to the chart's retained-earnings
                            account (silver_main_accounts.is_retained_earnings):
                            pre-acquisition profit is pre-acquisition equity,
                            and konsol's acquired balance sheet nets to that
                            equity. So line (0) sums to zero on its own.
     (1) equity_eliminated  each acquired-balance row whose account the chart
                            declares as equity (silver_main_accounts.is_equity):
                            -(book amount), so the credit balance konsol
                            recorded becomes a debit here (100%, whatever the
                            share: pre-acquisition equity is never group
                            reserves)
     (2) fva                Dr fair_value_adjustment_account by the sum of the
                            fair-value adjustments (100%)
     (3) goodwill           Dr goodwill_account by consideration (+ capitalised
                            costs, see 6) + NCI - (net assets + FVA), when that
                            figure is positive
     (3b) bargain_gain      when it is negative (the price is below the fair
                            value acquired), per the group's bargain_purchase
                            policy (row J4):
                              'Recognise gain': Cr bargain_purchase_gain_account
                                         (P&L) by the shortfall, and no goodwill
                                         line (IFRS 3.34: a gain, never negative
                                         goodwill);
                              'Refuse':  the deal posts NOTHING here, and
                                         assert_bargain_purchase_refused names
                                         it (deal, group, amount) so the build
                                         stops until konsol's Business
                                         Combination is reassessed (IFRS 3.36).
                            Any other value posts as 'Recognise gain'; row J7's
                            guard names an undeclared policy.
     (4) investment         Cr investment_account by the consideration
     (5) nci                Cr nci_account when share_acquired_pct < 100, per
                            the group's nci_measurement:
                              'partial': (net assets + FVA) x (1 - share), the
                                         NCI's share of the fair-value net
                                         assets, so goodwill = consideration
                                         - (net assets + FVA) x share;
                              'full':    consideration / share x (1 - share),
                                         the NCI at fair value implied by the
                                         price paid, so goodwill includes the
                                         NCI's share (design §1a).
                            Any other value posts as 'partial'; row J7's
                            guard names an undeclared policy.
     (6) costs / proceeds   each business_combination_costs row of the deal,
                            translated like the consideration, per the group's
                            acquisition_costs_treatment (row J4):
                              'Expense':    Dr acquisition_costs_account (P&L,
                                            role 'costs') / Cr the settlement
                                            account (role 'proceeds') per line
                                            (IFRS 3.53: costs of the period,
                                            outside goodwill);
                              'Capitalise': the costs join the consideration,
                                            so goodwill (3) is higher by the
                                            costs, and only the Cr to the
                                            settlement account is posted per
                                            line (role 'proceeds').
                            The settlement account is the group's
                            disposal_proceeds_account: the account the group
                            settles deal cash through (the design calls it
                            "proceeds-or-payable"; one declared account serves
                            both directions). Any other value posts as
                            'Expense'. The capitalised costs do not enter the
                            'full' NCI measurement: the price paid is the
                            fair-value signal, the deal's costs are not.

   Net assets at acquisition = -(sum of the eliminated equity), the figure the
   equity lines carry, so the journal closes whatever the asset and liability
   rows of the acquired balance sheet sum to (measurement_basis
   'acquired_balances').

   Currency: the consideration lines are translated from their own currency,
   and the acquired balances and the opening balances from the entity's
   accounting currency (epm_staging.entities, konsol's registry), to the
   group's reporting currency at the acquisition period's governed Closing
   rate, the period mapped through rate_period_map() like every trial-balance
   translation. A line already in group currency translates at 1. When a deal
   has no consideration lines, the header's total_consideration is used,
   translated from the header's consideration_currency the same way.

   A missing rate stops the deal, it never zeroes it (row J9, PR #203 review
   3 + 4): every translation INNER JOINs the deal's rate set (deal_rates), so
   a currency with no governed Closing rate for the period matches nothing,
   and the line counts below then drop the whole deal. Before, a LEFT JOIN
   miss read 0 under join_use_nulls = 0: an unrated consideration currency
   booked consideration 0 and a false bargain gain (or a 'Refuse' stop for
   the wrong reason), and an unrated entity currency booked net assets 0 and
   goodwill = consideration. assert_deal_rate_resolved names the pair (deal,
   from, to, period) before this model runs.

   Periods come from epm_staging.fiscal_periods by start_date <= date <=
   end_date, never from the month: a Closing period (one day inside the last
   Regular period) is skipped, so the deal lands in the Regular period.

   line_no: 0 for every opening-balance line, the child table's idx for the
   equity lines, then 101 fva, 102 goodwill, 103 investment, 104 nci,
   105 bargain_gain, 110 + idx for a costs debit and 130 + idx for its
   settlement credit. #}

with group_policy as (
    select
        consolidation_group,
        reporting_currency,
        nci_measurement,
        goodwill_treatment,
        acquisition_costs_treatment,
        bargain_purchase,
        goodwill_account,
        fair_value_adjustment_account,
        investment_account,
        nci_account,
        bargain_purchase_gain_account,
        disposal_proceeds_account,
        acquisition_costs_account
    from {{ source('epm_gold', 'consolidation_groups') }}
    where data_area_id = ''
),

{# the calendar period holding the acquisition date; the lowest-numbered
   non-Closing period whose span holds it. A range condition is not a
   ClickHouse join key, so the calendar is cross-joined and filtered. #}
deal_period as (
    select
        bc.name as deal,
        argMin(toUInt16(fp.fiscal_year), (toUInt16(fp.fiscal_year), toUInt16(fp.fiscal_period))) as fiscal_year,
        argMin(toUInt16(fp.fiscal_period), (toUInt16(fp.fiscal_year), toUInt16(fp.fiscal_period))) as fiscal_period
    from {{ source('epm_staging', 'business_combinations') }} as bc
    cross join {{ source('epm_staging', 'fiscal_periods') }} as fp
    where fp.start_date <= bc.acquisition_date
      and fp.end_date >= bc.acquisition_date
      and fp.period_type != 'Closing'
    group by bc.name
),

entity_currency as (
    select data_area_id, any(accounting_currency) as accounting_currency
    from {{ source('epm_staging', 'entities') }}
    group by data_area_id
),

deals as (
    select
        bc.name as deal,
        bc.consolidation_group as consolidation_group,
        bc.acquired_entity as data_area_id,
        bc.acquisition_date as acquisition_date,
        toFloat64(bc.share_acquired_pct) as share_acquired_pct,
        toFloat64(bc.total_consideration) as header_consideration,
        bc.consideration_currency as consideration_currency,
        dp.fiscal_year as fiscal_year,
        dp.fiscal_period as fiscal_period,
        if(rpm.mapped = 1, rpm.rate_year, dp.fiscal_year) as rate_year,
        if(rpm.mapped = 1, rpm.rate_period, dp.fiscal_period) as rate_period,
        ec.accounting_currency as entity_currency,
        gp.reporting_currency as reporting_currency,
        gp.nci_measurement as nci_measurement,
        gp.bargain_purchase as bargain_purchase,
        gp.acquisition_costs_treatment as acquisition_costs_treatment,
        gp.goodwill_account as goodwill_account,
        gp.fair_value_adjustment_account as fair_value_adjustment_account,
        gp.investment_account as investment_account,
        gp.nci_account as nci_account,
        gp.bargain_purchase_gain_account as bargain_purchase_gain_account,
        gp.acquisition_costs_account as acquisition_costs_account,
        gp.disposal_proceeds_account as settlement_account,
        concat('ACQ-', bc.consolidation_group, '-', bc.acquired_entity, '-', toString(bc.acquisition_date)) as journal_id
    from {{ source('epm_staging', 'business_combinations') }} as bc
    inner join group_policy as gp
        on gp.consolidation_group = bc.consolidation_group
    inner join deal_period as dp
        on dp.deal = bc.name
    left join {{ rate_period_map() }} as rpm
        on rpm.fiscal_year = dp.fiscal_year
        and rpm.fiscal_period = dp.fiscal_period
    left join entity_currency as ec
        on ec.data_area_id = bc.acquired_entity
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

{# the rates a deal may translate at (row J9): the governed Closing rates into
   the group's currency for the deal's rate period, plus 1 for the group
   currency itself (a governed row quoting the group currency against itself
   is left out, so it cannot double a line). Every translation below INNER
   JOINs this set on the line's currency: a currency with no rate matches
   nothing, and the deal is dropped by the line counts that follow. #}
deal_rates as (
    select
        d.deal as deal,
        cr.from_currency as from_currency,
        cr.closing_rate as rate
    from deals as d
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
    from deals
),

{# each deal's rate from the entity's currency into the group's; no row when
   the entity's currency is unrated (or the entity is not in the registry, so
   its currency reads ''), and then no acquired or opening balance posts #}
deal_entity_rate as (
    select
        d.deal as deal,
        r.rate as entity_rate
    from deals as d
    inner join deal_rates as r
        on r.deal = d.deal
        and r.from_currency = d.entity_currency
),

{# consideration in group currency: the lines translated at the closing rate,
   or the header figure when the deal has no lines. A deal keeps its
   consideration only when EVERY line found a rate (n_rated = n_lines): a
   line dropped by the INNER JOIN would understate the price and book a
   false bargain, so the deal posts nothing instead. #}
consideration_line_count as (
    select parent as deal, count() as n_lines
    from {{ source('epm_staging', 'business_combination_consideration') }}
    group by parent
),

consideration_lines as (
    select
        d.deal as deal,
        count() as n_rated,
        sum(toFloat64(c.amount) * r.rate) as consideration
    from {{ source('epm_staging', 'business_combination_consideration') }} as c
    inner join deals as d
        on d.deal = c.parent
    inner join deal_rates as r
        on r.deal = d.deal
        and r.from_currency = c.currency
    group by d.deal
),

{# the header's total_consideration, stated in consideration_currency
   (_staging__sources.yml), translated the same way; a zero header needs no
   rate. Named apart from the header_consideration column: ClickHouse reads a
   CTE name inside an expression as a scalar subquery. #}
header_consideration_rated as (
    select
        d.deal as deal,
        d.header_consideration * r.rate as consideration
    from deals as d
    inner join deal_rates as r
        on r.deal = d.deal
        and r.from_currency = d.consideration_currency
    where abs(d.header_consideration) > 0.005

    union all

    select
        deal,
        header_consideration as consideration
    from deals
    where abs(header_consideration) <= 0.005
),

consideration as (
    select
        cl.deal as deal,
        cl.consideration as consideration
    from consideration_lines as cl
    inner join consideration_line_count as lc
        on lc.deal = cl.deal
    where lc.n_lines = cl.n_rated

    union all

    select
        h.deal as deal,
        h.consideration as consideration
    from header_consideration_rated as h
    left join consideration_line_count as lc
        on lc.deal = h.deal
    where coalesce(lc.n_lines, 0) = 0
),

{# line (6): the deal's acquisition costs, each translated from its own
   currency like a consideration line; the same all-or-nothing rule
   (figures_raw compares n_rated with the deal's cost rows) #}
cost_line_count as (
    select parent as deal, count() as n_lines
    from {{ source('epm_staging', 'business_combination_costs') }}
    group by parent
),

cost_lines as (
    select
        d.deal as deal,
        cc.idx as idx,
        cc.kind as kind,
        toFloat64(cc.amount) * r.rate as amount
    from {{ source('epm_staging', 'business_combination_costs') }} as cc
    inner join deals as d
        on d.deal = cc.parent
    inner join deal_rates as r
        on r.deal = d.deal
        and r.from_currency = cc.currency
),

costs_total as (
    select deal, count() as n_rated, sum(amount) as costs
    from cost_lines
    group by deal
),

{# the acquired balance sheet konsol recorded, translated to group currency #}
acquired_balances as (
    select
        d.deal as deal,
        ab.idx as idx,
        ab.main_account as main_account,
        ma.account_name as account_name,
        ma.is_equity as is_equity,
        toFloat64(ab.book_amount) * er.entity_rate as book_amount,
        toFloat64(ab.fair_value_adjustment) * er.entity_rate as fair_value_adjustment
    from {{ source('epm_staging', 'business_combination_acquired_balances') }} as ab
    inner join deals as d
        on d.deal = ab.parent
    inner join deal_entity_rate as er
        on er.deal = d.deal
    left join {{ ref('silver_main_accounts') }} as ma
        on ma.main_account_id = ab.main_account
),

measured as (
    select
        deal,
        count() as n_balance_rows,
        -sumIf(book_amount, is_equity = 1) as net_assets,
        sum(fair_value_adjustment) as fva
    from acquired_balances
    group by deal
),

figures_raw as (
    select
        d.deal as deal,
        d.consolidation_group as consolidation_group,
        d.data_area_id as data_area_id,
        d.fiscal_year as fiscal_year,
        d.fiscal_period as fiscal_period,
        d.acquisition_date as acquisition_date,
        d.journal_id as journal_id,
        d.bargain_purchase as bargain_purchase,
        d.acquisition_costs_treatment as acquisition_costs_treatment,
        d.goodwill_account as goodwill_account,
        d.fair_value_adjustment_account as fair_value_adjustment_account,
        d.investment_account as investment_account,
        d.nci_account as nci_account,
        d.bargain_purchase_gain_account as bargain_purchase_gain_account,
        d.acquisition_costs_account as acquisition_costs_account,
        d.settlement_account as settlement_account,
        c.consideration as consideration,
        {# line (6): capitalised costs join the consideration in goodwill;
           expensed costs stay out of it. A deal with no costs rows joins
           nothing (0 under join_use_nulls = 0, NULL otherwise). #}
        if(d.acquisition_costs_treatment = 'Capitalise', coalesce(ct.costs, 0.0), 0.0) as capitalised_costs,
        m.net_assets as net_assets,
        m.fva as fva,
        d.share_acquired_pct / 100.0 as share,
        {# line (5): the NCI's share of the fair-value net assets ('partial'),
           or the NCI at the fair value the price implies ('full'); nothing at
           100%, and nothing under 'full' with a zero share (no division).
           The minority factor is (100 - pct) / 100, not 1 - pct / 100: the
           former is exact in Float64 for a whole-number percentage, the
           latter leaves 0.19999999999999996 on an 80% deal. #}
        multiIf(
            d.share_acquired_pct >= 100.0, 0.0,
            d.nci_measurement = 'full' and d.share_acquired_pct > 0.0,
                c.consideration / (d.share_acquired_pct / 100.0) * ((100.0 - d.share_acquired_pct) / 100.0),
            (m.net_assets + m.fva) * ((100.0 - d.share_acquired_pct) / 100.0)
        ) as nci,
        'acquired_balances' as measurement_basis
    from deals as d
    inner join consideration as c
        on c.deal = d.deal
    inner join measured as m
        on m.deal = d.deal
    left join costs_total as ct
        on ct.deal = d.deal
    left join cost_line_count as lc
        on lc.deal = d.deal
    where m.n_balance_rows > 0
      {# row J9: every cost row found its rate, or the deal posts nothing #}
      and coalesce(lc.n_lines, 0) = coalesce(ct.n_rated, 0)
),

{# goodwill (3) or, when negative, the bargain (3b): consideration + capitalised
   costs + NCI - (net assets + FVA). Under bargain_purchase = 'Refuse' a deal
   with a negative figure is dropped here, so none of its lines post
   (assert_bargain_purchase_refused names it). A separate CTE so the WHERE
   reads the computed figure, not an alias ClickHouse would re-expand. #}
figures as (
    select
        *,
        consideration + capitalised_costs + nci - (net_assets + fva) as goodwill_raw
    from figures_raw
    where not (
        bargain_purchase = 'Refuse'
        and consideration + capitalised_costs + nci - (net_assets + fva) < -0.005
    )
),

{# chart names for the declared accounts; '' when the chart lacks the code #}
chart as (
    select main_account_id, any(account_name) as account_name
    from {{ ref('silver_main_accounts') }}
    group by main_account_id
),

{# line (0): the entity's balance-sheet position at the last period-end
   before the acquisition period, from the entity trial balance (which knows
   every period the entity has, in or out of the ownership window), in local
   currency: the cumulative signed movements up to that period, year-end
   close rows included. A tuple comparison, never a date or month. #}
pre_acquisition_balances as (
    select
        f.deal as deal,
        tb.main_account as main_account,
        any(tb.account_name) as account_name,
        sum(toFloat64(tb.period_debit) - toFloat64(tb.period_credit)) as local_balance
    from {{ ref('gold_trial_balance') }} as tb
    inner join figures as f
        on f.data_area_id = tb.data_area_id
    where tb.is_balance_sheet = 1
      and (toUInt16(tb.fiscal_year), toUInt16(tb.fiscal_period)) < (f.fiscal_year, f.fiscal_period)
    group by f.deal, tb.main_account
),

opening_raw as (
    select
        pb.deal as deal,
        pb.main_account as main_account,
        pb.account_name as account_name,
        pb.local_balance * er.entity_rate as adjustment_amount
    from pre_acquisition_balances as pb
    inner join deal_entity_rate as er
        on er.deal = pb.deal
),

{# the current-year result still sitting in the P&L accounts at that
   period-end: what the balance-sheet accounts alone do not sum to #}
opening_residual as (
    select
        deal,
        -sum(adjustment_amount) as residual_amount
    from opening_raw
    group by deal
    having abs(residual_amount) > 0.005
),

opening_lines as (
    select
        f.deal as deal,
        f.consolidation_group as consolidation_group,
        f.data_area_id as data_area_id,
        f.fiscal_year as fiscal_year,
        f.fiscal_period as fiscal_period,
        o.main_account as main_account,
        o.account_name as account_name,
        o.adjustment_amount as adjustment_amount,
        f.acquisition_date as acquisition_date,
        f.journal_id as journal_id,
        toUInt16(0) as line_no,
        'opening_balance' as account_role,
        f.measurement_basis as measurement_basis
    from opening_raw as o
    inner join figures as f
        on f.deal = o.deal
    where abs(o.adjustment_amount) > 0.005
),

{# line (0)'s balancing line, to the chart's retained-earnings account
   (silver_main_accounts.is_retained_earnings; '' when the chart flags none,
   which row J7's guard names). Scalar subqueries: one chart, one account. #}
opening_residual_lines as (
    select
        f.deal as deal,
        f.consolidation_group as consolidation_group,
        f.data_area_id as data_area_id,
        f.fiscal_year as fiscal_year,
        f.fiscal_period as fiscal_period,
        (select anyIf(main_account_id, is_retained_earnings = 1) from {{ ref('silver_main_accounts') }}) as main_account,
        (select anyIf(account_name, is_retained_earnings = 1) from {{ ref('silver_main_accounts') }}) as account_name,
        r.residual_amount as adjustment_amount,
        f.acquisition_date as acquisition_date,
        f.journal_id as journal_id,
        toUInt16(0) as line_no,
        'opening_balance' as account_role,
        f.measurement_basis as measurement_basis
    from opening_residual as r
    inner join figures as f
        on f.deal = r.deal
),

equity_lines as (
    select
        f.deal as deal,
        f.consolidation_group as consolidation_group,
        f.data_area_id as data_area_id,
        f.fiscal_year as fiscal_year,
        f.fiscal_period as fiscal_period,
        ab.main_account as main_account,
        ab.account_name as account_name,
        -ab.book_amount as adjustment_amount,
        f.acquisition_date as acquisition_date,
        f.journal_id as journal_id,
        toUInt16(ab.idx) as line_no,
        'equity_eliminated' as account_role,
        f.measurement_basis as measurement_basis
    from acquired_balances as ab
    inner join figures as f
        on f.deal = ab.deal
    where ab.is_equity = 1
),

{# one row per fixed line of each deal; a zero line (no FVA, 100% share, no
   bargain) is left out. goodwill_raw = consideration + capitalised costs +
   NCI - (net assets + FVA): the amount that closes the journal, and design
   §4 line 3 under either NCI policy; positive it is goodwill (3), negative
   the bargain gain (3b), so exactly one of the two lines survives. #}
fixed_raw as (
    select
        deal,
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        acquisition_date,
        journal_id,
        measurement_basis,
        line_account,
        line_amount,
        line_no,
        account_role,
        default_name
    from figures
    array join
        [fair_value_adjustment_account, goodwill_account, investment_account, nci_account, bargain_purchase_gain_account] as line_account,
        [fva, greatest(goodwill_raw, 0.0), -consideration, -nci, least(goodwill_raw, 0.0)] as line_amount,
        [toUInt16(101), toUInt16(102), toUInt16(103), toUInt16(104), toUInt16(105)] as line_no,
        ['fva', 'goodwill', 'investment', 'nci', 'bargain_gain'] as account_role,
        ['Fair value adjustment on acquisition', 'Goodwill on acquisition', 'Investment in subsidiary eliminated', 'Non-controlling interest at acquisition', 'Gain on bargain purchase'] as default_name
    where abs(line_amount) > 0.005
),

{# line (6): per costs row, the P&L debit (Expense only; under Capitalise the
   debit sits inside goodwill) and the settlement credit (both treatments).
   Joined first, then ARRAY JOINed from one source: ClickHouse reads ARRAY
   JOIN before JOIN and cannot fan out over joined columns. #}
cost_figures as (
    select
        f.deal as deal,
        f.consolidation_group as consolidation_group,
        f.data_area_id as data_area_id,
        f.fiscal_year as fiscal_year,
        f.fiscal_period as fiscal_period,
        f.acquisition_date as acquisition_date,
        f.journal_id as journal_id,
        f.measurement_basis as measurement_basis,
        f.acquisition_costs_account as acquisition_costs_account,
        f.settlement_account as settlement_account,
        if(f.acquisition_costs_treatment = 'Capitalise', 0.0, cl.amount) as expensed_amount,
        cl.amount as settled_amount,
        toUInt16(110 + cl.idx) as debit_line_no,
        toUInt16(130 + cl.idx) as credit_line_no,
        cl.kind as kind
    from cost_lines as cl
    inner join figures as f
        on f.deal = cl.deal
),

cost_raw as (
    select
        deal,
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        acquisition_date,
        journal_id,
        measurement_basis,
        line_account,
        line_amount,
        line_no,
        account_role,
        default_name
    from cost_figures
    array join
        [acquisition_costs_account, settlement_account] as line_account,
        [expensed_amount, -settled_amount] as line_amount,
        [debit_line_no, credit_line_no] as line_no,
        ['costs', 'proceeds'] as account_role,
        [concat('Acquisition costs: ', kind), concat('Acquisition costs settled: ', kind)] as default_name
    where abs(line_amount) > 0.005
),

fixed_and_cost_raw as (
    select * from fixed_raw
    union all
    select * from cost_raw
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
        l.acquisition_date as acquisition_date,
        l.journal_id as journal_id,
        l.line_no as line_no,
        l.account_role as account_role,
        l.measurement_basis as measurement_basis
    from fixed_and_cost_raw as l
    left join chart as ch
        on ch.main_account_id = l.line_account
),

journal as (
    select * from opening_lines
    union all
    select * from opening_residual_lines
    union all
    select * from equity_lines
    union all
    select * from fixed_lines
)

select
    consolidation_group,
    data_area_id,
    fiscal_year,
    toUInt8(fiscal_period) as fiscal_period,
    main_account,
    account_name,
    'acquisition' as adjustment_type,
    adjustment_amount,
    acquisition_date,
    journal_id,
    line_no,
    account_role,
    deal,
    measurement_basis
from journal
