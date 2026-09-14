{#
    The next year's file carries the result in the account the close posted
    it to (konsolidat#199, PR 200 re-review finding 2).

    silver_tb_movements closes a period-end-balance year by moving the P&L
    balances into the chart's flagged retained-earnings account in the
    Closing period. The next year's first file must then list that account
    with the result in it. When it does not — the ERP keeps the result in
    another equity code, or the flag sits on the wrong account — the spine
    reads the flagged account as 0 in that first period and reverses the
    close as activity. The symptom: retained earnings shows minus the year's
    result at P1 while another equity code shows plus the result, and every
    statement still balances, so nothing else names it.

    One row per year-end close on the retained-earnings key whose entity's
    first claimed period after the close has no source row for that key
    (data_area_id, fiscal_year = the closed year, main_account). Warn
    severity: the figures are wrong for two equity lines, not for the
    build, and the fix is in konsol (flag the account the files really
    use) or in the upload, not in the warehouse.
#}

{{ config(severity='warn') }}

with closes as (

    {# the retained-earnings row of every synthesized close #}
    select
        m.data_area_id as data_area_id,
        m.fiscal_year as fiscal_year,
        m.fiscal_period as fiscal_period,
        m.main_account as main_account
    from {{ ref('silver_tb_movements') }} as m
    inner join {{ ref('silver_main_accounts') }} as ma
        on ma.main_account_id = m.main_account
    where m.movement_kind = 'year_end_close'
      and m.partner_data_area_id = ''
      and ma.is_retained_earnings = 1

),

claimed_periods as (

    select distinct
        data_area_id,
        fiscal_year,
        fiscal_period
    from {{ ref('bronze_trial_balance_submissions') }}

),

first_period_after as (

    {# the entity's first claimed period that sorts after the close #}
    select
        c.data_area_id as data_area_id,
        c.fiscal_year as fiscal_year,
        c.main_account as main_account,
        min((p.fiscal_year, p.fiscal_period)) as next_period
    from closes as c
    inner join claimed_periods as p
        on p.data_area_id = c.data_area_id
    where (p.fiscal_year, p.fiscal_period) > (c.fiscal_year, c.fiscal_period)
    group by c.data_area_id, c.fiscal_year, c.main_account

),

carried as (

    {# the keys the files list, partner '' as the close posts it #}
    select distinct
        data_area_id,
        fiscal_year,
        fiscal_period,
        main_account
    from {{ ref('bronze_trial_balance_submissions') }}
    where partner_data_area_id = ''

)

select
    f.data_area_id as data_area_id,
    f.fiscal_year as fiscal_year,
    f.main_account as main_account
from first_period_after as f
{# a LEFT JOIN miss reads '' under join_use_nulls=0, as elsewhere in the project #}
left join carried as k
    on k.data_area_id = f.data_area_id
    and k.fiscal_year = tupleElement(f.next_period, 1)
    and k.fiscal_period = tupleElement(f.next_period, 2)
    and k.main_account = f.main_account
where k.main_account = ''
