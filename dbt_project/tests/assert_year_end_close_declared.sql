{#
    Every period-end-balance year that must be closed can be closed
    (konsolidat#199, PR 200 finding 1; re-review findings 1 and 3).

    A 'Period-end balance' file carries the year's P&L in its accounts until
    the year end; the next year's file starts them from zero, with the result
    moved into retained earnings — the ERP's year-end close, which the file
    never shows. silver_tb_movements re-creates that close as a synthetic
    post-close period in the fiscal year's Closing period
    (epm_staging.fiscal_periods, period_type = 'Closing'), posting the P&L
    balances to the chart's single retained-earnings account
    (silver_main_accounts.is_retained_earnings = 1). Without both it
    synthesizes nothing — and the next year's first period would then carry
    the reversal of the whole previous year's P&L as activity.

    So: one row per (entity, fiscal year) that NEEDS a close — its batches are
    period-end balances, a later fiscal year has data, and SOMETHING SITS IN
    A P&L ACCOUNT at the year's last claimed period (any P&L balance there is
    not 0 — not the net: silver_tb_movements closes every P&L key, so a year
    whose revenue and expenses cancel still needs its close; a
    balance-sheet-only entity, or a file that already zeroes its P&L, needs no
    close and is not held up by a missing Closing period or flag) — and LACKS
    a usable Closing period
    (none in the calendar for the year, or one that does not sort after the
    year's last claimed period: the close must post after the balances it
    closes) or a single retained-earnings account, with the reason. Error
    severity: the numbers downstream would be wrong for every P&L account of
    the next year.
#}

{{ config(severity='error') }}

with entity_years as (

    {# the entity's claimed periods per fiscal year, with the basis of the
       year's last one #}
    select
        data_area_id,
        fiscal_year,
        max(fiscal_period) as last_period,
        argMax(amount_basis, (fiscal_period, claimed_at)) as amount_basis
    from {{ ref('bronze_trial_balance_submissions') }}
    group by data_area_id, fiscal_year

),

years_with_successor as (

    select
        *,
        max(fiscal_year) over (partition by data_area_id) as last_year
    from entity_years

),

pnl_keys as (

    {# the P&L balances at the year's last claimed period, at the model's
       key grain (account × partner), the way silver_tb_movements sees them #}
    select
        b.data_area_id as data_area_id,
        b.fiscal_year as fiscal_year,
        b.main_account as main_account,
        b.partner_data_area_id as partner_data_area_id,
        sum(b.debit_amount - b.credit_amount) as key_net
    from {{ ref('bronze_trial_balance_submissions') }} as b
    inner join entity_years as y
        on y.data_area_id = b.data_area_id
        and y.fiscal_year = b.fiscal_year
        and y.last_period = b.fiscal_period
    inner join {{ ref('silver_main_accounts') }} as ma
        on ma.main_account_id = b.main_account
    where ma.is_pnl = 1
    group by b.data_area_id, b.fiscal_year, b.main_account, b.partner_data_area_id

),

pnl_totals as (

    {# silver_tb_movements zeroes EVERY P&L key at the close and moves their
       sum into retained earnings, so the year needs a close as soon as ANY
       P&L key holds a balance — not only when the net result is not 0: a
       year whose revenue and expenses cancel still leaves balances the next
       year's file restarts from 0, and without the close their reversal
       would read as activity. Only all-zero P&L means nothing to close. #}
    select
        data_area_id,
        fiscal_year,
        sum(abs(key_net)) as pnl_total
    from pnl_keys
    group by data_area_id, fiscal_year
    having pnl_total != 0

),

closing_periods as (

    select
        fiscal_year,
        min(fiscal_period) as closing_period
    from {{ source('epm_staging', 'fiscal_periods') }}
    where period_type = 'Closing'
    group by fiscal_year

),

retained_earnings as (

    select count() as retained_accounts
    from {{ ref('silver_main_accounts') }}
    where is_retained_earnings = 1

),

candidates as (

    select
        y.data_area_id as data_area_id,
        y.fiscal_year as fiscal_year,
        y.last_period as last_period,
        {# a LEFT JOIN miss reads 0 under join_use_nulls=0, and no calendar numbers a period 0 #}
        cp.closing_period as closing_period,
        {# the Closing period is usable only when it sorts after the year's
           last claimed period (re-review finding 3), which is also where
           silver_tb_movements posts the close; the same condition as its
           years_to_close #}
        cp.closing_period > y.last_period as closing_period_usable,
        re.retained_accounts as retained_accounts
    from years_with_successor as y
    inner join pnl_totals as t
        on t.data_area_id = y.data_area_id
        and t.fiscal_year = y.fiscal_year
    left join closing_periods as cp
        on cp.fiscal_year = y.fiscal_year
    cross join retained_earnings as re
    where y.amount_basis = 'Period-end balance'
      and y.fiscal_year < y.last_year

)

select
    data_area_id,
    fiscal_year,
    multiIf(
        not closing_period_usable and retained_accounts != 1,
            if(closing_period = 0,
               'no Closing period in the fiscal calendar and no single retained-earnings account in the chart',
               concat('the Closing period P', toString(closing_period), ' does not sort after the year''s last claimed period P',
                      toString(last_period), ', and no single retained-earnings account in the chart')),
        closing_period = 0,
            'no Closing period in the fiscal calendar for the year',
        not closing_period_usable,
            concat('the Closing period P', toString(closing_period), ' does not sort after the year''s last claimed period P',
                   toString(last_period)),
        retained_accounts = 0,
            'the chart flags no retained-earnings account',
        concat('the chart flags ', toString(retained_accounts), ' retained-earnings accounts, expected one')
    ) as reason
from candidates
where not closing_period_usable
   or retained_accounts != 1
