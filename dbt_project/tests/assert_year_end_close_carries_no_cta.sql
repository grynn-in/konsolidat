{#
    konsolidat#259 (option #259-1, decided by Deepak Pai, 6 Oct 2026): the
    year-end close moves amounts that are already translated, so it creates no
    exchange difference.

    silver_tb_movements closes a period-end-balance year in the year's Closing
    period: every P&L key is reversed and the result moves into the
    retained-earnings account (posting_layer 'Year-end close' in
    silver_gl_entries). Translated naively, the reversal goes at the period's
    average rate and retained earnings at its own declared rate, so the close
    leaves -(the year's P&L) x (average - closing) in that period's CTA, which
    cancels the year's CTA and moves it into retained earnings every year.

    Under #259-1 retained earnings is credited with the year's TRANSLATED
    result, whatever the account's fx_method declares, and the P&L reversal
    returns each P&L key's translated year to exactly zero. So, for every
    (group, entity, Closing-type period) that carries a year-end close:

        | CTA of that period |                                   <= 0.01
        | the year's translated P&L, summed through that period | <= 0.01

    It also names an ERP-POSTED close: a Closing period with no 'Year-end
    close' rows but P&L activity, whose CTA is not zero. The warehouse cannot
    tell such a close from ordinary activity, so it translates it as activity
    and does not guess; this test says where that happened.

    Warn severity (plan §3 R3): the consolidated statements still balance,
    the split between retained earnings and CTA is what is wrong.

    Kinds:
      year_end_close    the synthesized close, checked on both conditions
      erp_posted_close  P&L activity in a Closing period, checked on CTA
#}

{{ config(severity='warn') }}

with closing_periods as (
    select distinct fiscal_year, fiscal_period
    from {{ source('epm_staging', 'fiscal_periods') }}
    where period_type = 'Closing'
),

close_marks as (
    select distinct data_area_id, fiscal_year, fiscal_period
    from {{ ref('silver_gl_entries') }}
    where posting_layer = 'Year-end close'
),

{# every (group, entity, Closing period) the consolidation has rows in #}
closing_rows as (
    select
        ctb.consolidation_group as consolidation_group,
        ctb.data_area_id as data_area_id,
        ctb.fiscal_year as fiscal_year,
        ctb.fiscal_period as fiscal_period,
        countIf(ctb.is_pnl = 1 and ctb.local_amount != 0) as pnl_rows
    from {{ ref('gold_consolidated_trial_balance') }} as ctb
    inner join closing_periods as cp
        on cp.fiscal_year = ctb.fiscal_year
        and cp.fiscal_period = ctb.fiscal_period
    group by ctb.consolidation_group, ctb.data_area_id, ctb.fiscal_year, ctb.fiscal_period
),

{# the year's translated P&L through the Closing period #}
pnl_to_close as (
    select
        c.consolidation_group as consolidation_group,
        c.data_area_id as data_area_id,
        c.fiscal_year as fiscal_year,
        c.fiscal_period as fiscal_period,
        sum(ifNull(ctb.translated_amount, 0)) as translated_pnl
    from closing_rows as c
    inner join {{ ref('gold_consolidated_trial_balance') }} as ctb
        on ctb.consolidation_group = c.consolidation_group
        and ctb.data_area_id = c.data_area_id
        and ctb.fiscal_year = c.fiscal_year
    where ctb.fiscal_period <= c.fiscal_period
      and ctb.is_pnl = 1
    group by c.consolidation_group, c.data_area_id, c.fiscal_year, c.fiscal_period
),

checked as (
    select
        c.consolidation_group as consolidation_group,
        c.data_area_id as data_area_id,
        c.fiscal_year as fiscal_year,
        c.fiscal_period as fiscal_period,
        multiIf(
            m.data_area_id != '', 'year_end_close',
            c.pnl_rows > 0, 'erp_posted_close',
            ''
        ) as close_kind,
        ifNull(fx.cta_amount, 0) as cta_amount,
        ifNull(p.translated_pnl, 0) as translated_pnl
    from closing_rows as c
    left join close_marks as m
        on m.data_area_id = c.data_area_id
        and m.fiscal_year = c.fiscal_year
        and m.fiscal_period = c.fiscal_period
    left join {{ ref('gold_fx_revaluation') }} as fx
        on fx.consolidation_group = c.consolidation_group
        and fx.data_area_id = c.data_area_id
        and fx.fiscal_year = c.fiscal_year
        and fx.fiscal_period = c.fiscal_period
    left join pnl_to_close as p
        on p.consolidation_group = c.consolidation_group
        and p.data_area_id = c.data_area_id
        and p.fiscal_year = c.fiscal_year
        and p.fiscal_period = c.fiscal_period
)

select
    consolidation_group,
    data_area_id,
    fiscal_year,
    fiscal_period,
    close_kind,
    cta_amount,
    translated_pnl,
    concat(
        'entity ', data_area_id, ' in group ', consolidation_group,
        ' at FY', toString(fiscal_year), ' P', toString(fiscal_period), ': ',
        if(close_kind = 'year_end_close',
           concat('the year-end close leaves CTA ', toString(round(cta_amount, 2)),
                  ' and the year''s translated P&L at ', toString(round(translated_pnl, 2)),
                  ' (konsolidat#259-1: both must be 0; retained earnings takes the translated result).'),
           concat('P&L activity in a Closing period (an ERP-posted close?) leaves CTA ',
                  toString(round(cta_amount, 2)),
                  ' (konsolidat#259: only a close konsol synthesizes is translated as a close).'))
    ) as problem
from checked
where (close_kind = 'year_end_close' and (abs(cta_amount) > 0.01 or abs(translated_pnl) > 0.01))
   or (close_kind = 'erp_posted_close' and abs(cta_amount) > 0.01)
