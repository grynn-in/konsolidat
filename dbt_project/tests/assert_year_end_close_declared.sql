{#
    Every period-end-balance year that must be closed can be closed
    (konsolidat#199, PR 200 finding 1).

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
    period-end balances, a later fiscal year has data, and no batch was
    claimed in the Closing period itself (a file that already holds the
    closed balances needs none) — and LACKS a Closing period or a single
    retained-earnings account, with the reason. Error severity: the numbers
    downstream would be wrong for every P&L account of the next year.
#}

{{ config(severity='error') }}

with entity_years as (

    {# the entity's claimed periods per fiscal year, with the basis of the
       year's last one #}
    select
        data_area_id,
        fiscal_year,
        argMax(amount_basis, (fiscal_period, claimed_at)) as amount_basis,
        groupUniqArray(fiscal_period) as claimed_periods
    from {{ ref('bronze_trial_balance_submissions') }}
    group by data_area_id, fiscal_year

),

years_with_successor as (

    select
        *,
        max(fiscal_year) over (partition by data_area_id) as last_year
    from entity_years

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

)

select
    y.data_area_id as data_area_id,
    y.fiscal_year as fiscal_year,
    multiIf(
        cp.closing_period = 0 and re.retained_accounts != 1,
            'no Closing period in the fiscal calendar and no single retained-earnings account in the chart',
        cp.closing_period = 0,
            'no Closing period in the fiscal calendar for the year',
        re.retained_accounts = 0,
            'the chart flags no retained-earnings account',
        concat('the chart flags ', toString(re.retained_accounts), ' retained-earnings accounts, expected one')
    ) as reason
from years_with_successor as y
{# a LEFT JOIN miss reads 0 under join_use_nulls=0, and no calendar numbers a period 0 #}
left join closing_periods as cp
    on cp.fiscal_year = y.fiscal_year
cross join retained_earnings as re
where y.amount_basis = 'Period-end balance'
  and y.fiscal_year < y.last_year
  and not has(y.claimed_periods, cp.closing_period)
  and (cp.closing_period = 0 or re.retained_accounts != 1)
