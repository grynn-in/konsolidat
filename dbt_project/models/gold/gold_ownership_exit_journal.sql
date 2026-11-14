{{
    config(
        materialized='table',
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# konsolidat#335, option A (decided 14 Nov 2026 by Deepak Pai; HMD on #335): automatic derecognition when an
   Ownership Period ends without a deal. Design note: konsol .claude/memory/active/tasks-p1-round2.md, T8 (chosen
   under the 5 Nov standing rule). Task X3: the FULL method.

   One journal per exit event (G, E, P) of ownership_exits() (X1: E live in G the previous declared period, not
   live in P, not ended by its own full Business Disposal), journal_id EXIT_<group>_<entity>_<FY>_<period>,
   adjustment_type 'ownership_exit', posted in P, in group currency, dimensions blank (deal journal rule, decided
   3 Oct 2026). It reverses what the group carried for E up to the period BEFORE P, read from the layers that
   posted it, and is balanced by construction:
     (0)   derecognised  every non-equity balance-sheet account of E: layer 1 (gold_consolidated_trial_balance,
                         group_amount, 100% for full) and the acquisition journal's opening_balance lines.
                         Equity is the chart's silver_main_accounts.is_equity, the classification
                         gold_business_disposal_journal line (0) uses.
     (101) goodwill      the acquisition journal's goodwill line(s), net of gold_goodwill_amortisation_journal
     (102) fva           the acquisition journal's fair-value adjustment line(s)
     (103) cta           the 'CTA' line: gold_fx_revaluation (100%) plus gold_nci_attribution_journal's CTA leg,
                         so the group's share is recycled to P&L and the minority's share leaves inside NCI
                         (IAS 21.48, 21.48B)
     (104) nci           the NCI the acquisition journal credited plus gold_nci_attribution_journal's NCI lines
     (199) gain_loss     the root's exit_gain_loss_account (P&L): -(sum of every other line). There are no
                         proceeds: a debit is a loss of net assets + goodwill + FVA - NCI - CTA recycled.
   Each line is reversed on the account its source posted to, so the journal undoes exactly what was carried.
   Not reversed (IFRS 10.B98, as disposal line (0)): the equity accounts (pre-acquisition equity was eliminated;
   post-acquisition profit stays in group reserves) and the current year's P&L. Not reversed either: the
   parent's investment and the deal's settlement lines (the disposal journal leaves them too), and topside
   (a WARN names it, task X8). Layer 2 (IC) is never read: its 'left' row reverses the eliminations
   (gold_ic_reconciliation); gold_fully_consolidated_tb is never read (it unions this model).

   Methods. method_before 'full' (full_exits) and 'proportional' (proportional_exits, task X4) post here. An
   equity-method exit (task X5, EQ_INVEST) posts NOTHING yet: they are not refused and not posted wrong;
   assert_exit_derecognises_carried flags their carried balances until task X5 lands.

   The accounts come from the group's root row (data_area_id = ''), read with any() per column as
   gold_business_disposal_journal reads it. A group without a root row, or whose root declares no
   exit_gain_loss_account, posts nothing: assert_exit_accounts_declared (X2, ERROR) names it, and
   assert_exit_derecognises_carried flags the balances left behind.

   Known gap (not this task): gold_goodwill_amortisation_journal stops only at a Business Disposal, so under
   'Amortise' it keeps posting after a bare exit; assert_exit_derecognises_carried flags the goodwill then.

   line_no: 0 derecognised, 101 goodwill, 102 fva, 103 cta, 104 nci, 199 gain_loss. #}

with group_policy as (
    select
        consolidation_group,
        any(exit_gain_loss_account) as exit_gain_loss_account
    from {{ source('epm_gold', 'consolidation_groups') }}
    where data_area_id = ''
    group by consolidation_group
),

{# The exit events, read once: ClickHouse inlines a WITH subquery at every reference, and this one is the
   ownership graph on a period spine. #}
exit_events as (
    select
        x.consolidation_group as consolidation_group,
        x.data_area_id as data_area_id,
        toUInt16(x.fiscal_year) as fiscal_year,
        toUInt16(x.fiscal_period) as fiscal_period,
        x.method_before as method_before,
        x.end_date as end_date,
        gp.exit_gain_loss_account as exit_gain_loss_account,
        concat('EXIT_', x.consolidation_group, '_', x.data_area_id, '_',
               toString(x.fiscal_year), '_', toString(x.fiscal_period)) as journal_id
    from {{ ownership_exits() }} as x
    inner join group_policy as gp
        on gp.consolidation_group = x.consolidation_group
    where gp.exit_gain_loss_account != ''
),

{# task X3: the full method, 100% of what layer 1 carried #}
full_exits as (
    select * from exit_events where method_before = 'full'
),

{# task X4: a proportional exit (IFRS 11 joint operation) reverses what layer 1 carried at the carried share.
   Layer 1 already carries group_amount = translated x share of each period (nci_amount 0), so reversing the
   to-date group_amount is exactly the carried share, including after an earlier share step; gold_fx_revaluation's
   plug is on the group share too (its header, proportional), so the 'CTA' line needs no minority leg. No goodwill,
   FVA or NCI: a deal into a joint operation is refused. Same lines, same balancing line (199) as full. #}
proportional_exits as (
    select * from exit_events where method_before = 'proportional'
),

{# task X5 adds equity_exits (EQ_INVEST against the exit account, no CTA leg). Until then it posts nothing. #}
posting_exits_all as (
    select * from full_exits
    union all
    select * from proportional_exits
),

{# What an earlier journal already derecognised is not carried any more: after a re-entry (the
   joint_operation_gap shape, task X7) the next exit reverses only from the previous exit period on (that
   exit's journal reversed everything before it), and only after the latest full Business Disposal of E in G
   before P (its journal derecognised up to and including its period). ord = FY x 1000 + period. #}
previous_exit as (
    select
        consolidation_group, data_area_id, fiscal_year, fiscal_period,
        lagInFrame(toUInt32(fiscal_year) * 1000 + fiscal_period, 1, toUInt32(0)) over (
            partition by consolidation_group, data_area_id
            order by fiscal_year, fiscal_period
            rows between unbounded preceding and current row
        ) as previous_exit_ord
    from posting_exits_all
),

previous_disposal as (
    select
        x.consolidation_group as consolidation_group,
        x.data_area_id as data_area_id,
        x.fiscal_year as fiscal_year,
        x.fiscal_period as fiscal_period,
        max(toUInt32(d.fiscal_year) * 1000 + d.fiscal_period) as disposal_ord
    from posting_exits_all as x
    inner join (
        select distinct consolidation_group, data_area_id, fiscal_year, fiscal_period
        from {{ ref('gold_business_disposal_journal') }}
    ) as d
        on d.consolidation_group = x.consolidation_group
        and d.data_area_id = x.data_area_id
    where (toUInt16(d.fiscal_year), toUInt16(d.fiscal_period)) < (x.fiscal_year, x.fiscal_period)
    group by x.consolidation_group, x.data_area_id, x.fiscal_year, x.fiscal_period
),

{# join_use_nulls = 0: no earlier exit or disposal reads 0, so the lower bound is 0 (all history) #}
posting_exits as (
    select
        x.*,
        greatest(pe.previous_exit_ord, if(pd.disposal_ord = 0, toUInt32(0), pd.disposal_ord + 1)) as from_ord
    from posting_exits_all as x
    left join previous_exit as pe
        on pe.consolidation_group = x.consolidation_group and pe.data_area_id = x.data_area_id
        and pe.fiscal_year = x.fiscal_year and pe.fiscal_period = x.fiscal_period
    left join previous_disposal as pd
        on pd.consolidation_group = x.consolidation_group and pd.data_area_id = x.data_area_id
        and pd.fiscal_year = x.fiscal_year and pd.fiscal_period = x.fiscal_period
),

equity_accounts as (
    select main_account_id, max(is_equity) as is_equity, max(is_balance_sheet) as is_balance_sheet
    from {{ ref('silver_main_accounts') }}
    group by main_account_id
),

{# Every amount the group carries for (G, E) on the lines this journal reverses, by period, with the line it
   becomes. Unioned first and joined to the exits once. #}
carried_sources as (
    select
        ctb.consolidation_group as consolidation_group,
        ctb.data_area_id as data_area_id,
        toUInt16(ctb.fiscal_year) as fiscal_year,
        toUInt16(ctb.fiscal_period) as fiscal_period,
        ctb.main_account as main_account,
        ctb.account_name as account_name,
        toFloat64(coalesce(ctb.group_amount, 0.0)) as amount,
        toUInt16(0) as line_no,
        'derecognised' as account_role
    from {{ ref('gold_consolidated_trial_balance') }} as ctb
    left join equity_accounts as ea
        on ea.main_account_id = ctb.main_account
    where ctb.is_balance_sheet = 1
      and coalesce(ea.is_equity, 0) = 0

    union all

    select
        j.consolidation_group,
        j.data_area_id,
        toUInt16(j.fiscal_year),
        toUInt16(j.fiscal_period),
        j.main_account,
        j.account_name,
        toFloat64(j.adjustment_amount),
        multiIf(j.account_role = 'opening_balance', toUInt16(0), j.account_role = 'goodwill', toUInt16(101),
                j.account_role = 'fva', toUInt16(102), toUInt16(104)),
        if(j.account_role = 'opening_balance', 'derecognised', j.account_role)
    from {{ ref('gold_business_combination_journal') }} as j
    left join equity_accounts as ea
        on ea.main_account_id = j.main_account
    where j.account_role in ('goodwill', 'fva', 'nci')
       or (j.account_role = 'opening_balance' and coalesce(ea.is_balance_sheet, 0) = 1 and coalesce(ea.is_equity, 0) = 0)

    union all

    select
        a.consolidation_group,
        a.data_area_id,
        toUInt16(a.fiscal_year),
        toUInt16(a.fiscal_period),
        a.main_account,
        a.account_name,
        toFloat64(a.adjustment_amount),
        toUInt16(101),
        'goodwill'
    from {{ ref('gold_goodwill_amortisation_journal') }} as a
    where a.account_role = 'goodwill'

    union all

    select
        fx.consolidation_group,
        fx.data_area_id,
        toUInt16(fx.fiscal_year),
        toUInt16(fx.fiscal_period),
        fx.main_account,
        'CTA',
        toFloat64(fx.cta_amount),
        toUInt16(103),
        'cta'
    from {{ ref('gold_fx_revaluation') }} as fx

    union all

    select
        n.consolidation_group,
        n.data_area_id,
        toUInt16(n.fiscal_year),
        toUInt16(n.fiscal_period),
        n.main_account,
        n.account_name,
        toFloat64(n.amount),
        if(n.account_role = 'cta', toUInt16(103), toUInt16(104)),
        n.account_role
    from {{ ref('gold_nci_attribution_journal') }} as n
    where n.account_role in ('cta', 'nci')
),

{# the to-date carried amount per exit and line: every period BEFORE the exit period, by tuple, from the
   lower bound posting_exits sets #}
carried as (
    select
        x.consolidation_group as consolidation_group,
        x.data_area_id as data_area_id,
        x.fiscal_year as fiscal_year,
        x.fiscal_period as fiscal_period,
        x.journal_id as journal_id,
        x.end_date as end_date,
        x.exit_gain_loss_account as exit_gain_loss_account,
        s.main_account as main_account,
        s.line_no as line_no,
        s.account_role as account_role,
        any(s.account_name) as source_account_name,
        sum(s.amount) as carried_amount
    from carried_sources as s
    inner join posting_exits as x
        on x.consolidation_group = s.consolidation_group
        and x.data_area_id = s.data_area_id
    where (s.fiscal_year, s.fiscal_period) < (x.fiscal_year, x.fiscal_period)
      and toUInt32(s.fiscal_year) * 1000 + s.fiscal_period >= x.from_ord
    group by x.consolidation_group, x.data_area_id, x.fiscal_year, x.fiscal_period, x.journal_id, x.end_date,
             x.exit_gain_loss_account, s.main_account, s.line_no, s.account_role
),

reversal_lines as (
    select
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        journal_id,
        end_date,
        exit_gain_loss_account,
        main_account,
        source_account_name,
        -carried_amount as adjustment_amount,
        line_no,
        account_role
    from carried
    where abs(carried_amount) > {{ materiality_floor() }}
),

{# line (199): the counterpart of every other line. Its own alias, so no WHERE re-expands an aggregate. #}
balancing as (
    select
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        journal_id,
        end_date,
        exit_gain_loss_account,
        -sum(adjustment_amount) as balancing_amount
    from reversal_lines
    group by consolidation_group, data_area_id, fiscal_year, fiscal_period, journal_id, end_date,
             exit_gain_loss_account
),

chart as (
    select main_account_id, any(account_name) as account_name
    from {{ ref('silver_main_accounts') }}
    group by main_account_id
),

journal as (
    select
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        main_account,
        if(source_account_name != '', source_account_name, main_account) as account_name,
        adjustment_amount,
        end_date,
        journal_id,
        line_no,
        account_role
    from reversal_lines

    union all

    select
        b.consolidation_group,
        b.data_area_id,
        b.fiscal_year,
        b.fiscal_period,
        b.exit_gain_loss_account,
        if(ch.account_name != '', ch.account_name, 'Gain or loss on ownership exit'),
        b.balancing_amount,
        b.end_date,
        b.journal_id,
        toUInt16(199),
        'gain_loss'
    from balancing as b
    left join chart as ch
        on ch.main_account_id = b.exit_gain_loss_account
    where abs(b.balancing_amount) > {{ materiality_floor() }}
)

select
    consolidation_group,
    data_area_id,
    fiscal_year,
    toUInt8(fiscal_period) as fiscal_period,
    main_account,
    account_name,
    'ownership_exit' as adjustment_type,
    adjustment_amount,
    end_date,
    journal_id,
    line_no,
    account_role
from journal
