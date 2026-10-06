{#
    konsolidat#257 Q2 (decided by Deepak Pai, 6 Oct 2026): equity is never
    revalued. An equity account's translated movement is its local movement at
    the rate the row declares (historical, else the closing rate of the period
    it was posted in), whatever its fx_method. A balance sheet balance is
    retranslated at each closing rate (#257), but an equity balance is not:
    retranslating it would bury the exchange difference in equity lines and
    leave no separate component to recycle on disposal (IAS 21.39(c), .48).

    So on every equity row (is_equity = 1, from the chart):

        | translated_amount - local_amount x translation_rate | <= 0.01

    A revaluation shows up as exactly that difference: a filler row with
    local_amount = 0 and a translated amount, or a retranslation_amount on a
    row that moved.

    The one declared exception is the year-end close leg of the
    retained-earnings account (konsolidat#259-1, decided 6 Oct 2026): in a
    Closing-type period, retained earnings is credited with the year's
    translated result, not its local result at a rate. That leg is governed by
    assert_year_end_close_carries_no_cta, so this test leaves the
    retained-earnings account's rows in Closing periods to it. Nothing else is
    exempt: another equity account in a Closing period is still checked.
#}

with closing_periods as (
    select distinct fiscal_year, fiscal_period
    from {{ source('epm_staging', 'fiscal_periods') }}
    where period_type = 'Closing'
),

retained_earnings as (
    select main_account_id
    from {{ ref('silver_main_accounts') }}
    where is_retained_earnings = 1
)

select
    ctb.consolidation_group as consolidation_group,
    ctb.data_area_id as data_area_id,
    ctb.fiscal_year as fiscal_year,
    ctb.fiscal_period as fiscal_period,
    ctb.main_account as main_account,
    ctb.partner_data_area_id as partner_data_area_id,
    ctb.local_amount as local_amount,
    ctb.translation_rate as translation_rate,
    ctb.retranslation_amount as retranslation_amount,
    ctb.translated_amount as translated_amount,
    concat(
        'equity account ', ctb.main_account, ' of entity ', ctb.data_area_id,
        ' in group ', ctb.consolidation_group,
        ' at FY', toString(ctb.fiscal_year), ' P', toString(ctb.fiscal_period),
        ': translated ', toString(round(ifNull(ctb.translated_amount, 0), 2)),
        ', but the local movement ', toString(round(toFloat64(ctb.local_amount), 2)),
        ' at its rate ', toString(ctb.translation_rate),
        ' is ', toString(round(toFloat64(ctb.local_amount) * ifNull(ctb.translation_rate, 0), 2)),
        ' (konsolidat#257 Q2: equity is never revalued).'
    ) as problem
from {{ ref('gold_consolidated_trial_balance') }} as ctb
where ctb.is_equity = 1
  and abs(ifNull(ctb.translated_amount, 0) - toFloat64(ctb.local_amount) * ifNull(ctb.translation_rate, 0)) > 0.01
  and not (
      (ctb.fiscal_year, ctb.fiscal_period) in (select fiscal_year, fiscal_period from closing_periods)
      and ctb.main_account in (select main_account_id from retained_earnings)
  )
