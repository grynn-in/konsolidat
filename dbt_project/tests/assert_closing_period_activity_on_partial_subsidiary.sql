{{ config(severity='error') }}
{#
    konsol#117 pair 2 review, finding 4 (konsolidat#259 / #204 option (a)).
    The NCI attribution journal (gold_nci_attribution_journal) leaves out the
    synthesized year-end close by its marker, gold_trial_balance_by_partner.
    is_year_end_close = 1. A close the ERP posts itself carries no marker: in a
    Closing-type period it reads as P&L activity, and the journal would post
    Dr NCI / Cr retained earnings for the minority's share of the WHOLE year's
    reversal, silently (the CTA is 0 in the group currency, so
    assert_year_end_close_carries_no_cta does not name it).

    One row per (group, entity, FY, Closing period) of a full-method entity held
    below 100% that has P&L rows in the consolidated TB which are not marked as
    the year-end close. Σ amount is the translated P&L, so the size of the
    reversal is visible. The Closing period is identified as
    gold_consolidated_trial_balance does: fiscal_periods.period_type = 'Closing'.
    Fixture: test_fixtures/assert_closing_period_activity_on_partial_subsidiary
    (.must_flag.sql; nci_attribution_journal.sql is the passing case, its P13 rows
    are marked).
#}
with closing_periods as (
    select distinct fiscal_year, fiscal_period
    from {{ source('epm_staging', 'fiscal_periods') }}
    where period_type = 'Closing'
),

close_keys as (
    select distinct data_area_id, fiscal_year, fiscal_period, main_account
    from {{ ref('gold_trial_balance_by_partner') }}
    where is_year_end_close = 1
),

partial as (
    select distinct consolidation_group, data_area_id, fiscal_year, fiscal_period
    from {{ ref('gold_entity_ownership') }}
    where consolidation_method = 'full'
      and has_complete_chain = 1
      and effective_ownership_pct < 1 - 0.000001
)

select
    ctb.consolidation_group as consolidation_group,
    ctb.data_area_id as data_area_id,
    ctb.fiscal_year as fiscal_year,
    ctb.fiscal_period as fiscal_period,
    sum(toFloat64(ctb.translated_amount)) as unmarked_pnl_amount,
    concat('entity ', ctb.data_area_id, ' in group ', ctb.consolidation_group,
           ' is held below 100% and has unmarked P&L rows in Closing period FY',
           toString(ctb.fiscal_year), ' P', toString(ctb.fiscal_period), ' (sum ',
           toString(round(sum(toFloat64(ctb.translated_amount)), 2)),
           '): an unmarked year-end close in a Closing period would reverse the year''s NCI attribution; ',
           'mark it (konsolidat#259) or move the activity to a Regular period') as problem
from {{ ref('gold_consolidated_trial_balance') }} as ctb
inner join closing_periods as cp
    on cp.fiscal_year = ctb.fiscal_year
    and cp.fiscal_period = ctb.fiscal_period
inner join partial as p
    on p.consolidation_group = ctb.consolidation_group
    and p.data_area_id = ctb.data_area_id
    and p.fiscal_year = ctb.fiscal_year
    and p.fiscal_period = ctb.fiscal_period
where ctb.is_pnl = 1
  and (ctb.data_area_id, ctb.fiscal_year, ctb.fiscal_period, ctb.main_account)
      not in (select data_area_id, fiscal_year, fiscal_period, main_account from close_keys)
group by ctb.consolidation_group, ctb.data_area_id, ctb.fiscal_year, ctb.fiscal_period
having abs(sum(toFloat64(ctb.translated_amount))) > 0.000001
    or sumIf(1, abs(toFloat64(ctb.local_amount)) > 0.000001) > 0
