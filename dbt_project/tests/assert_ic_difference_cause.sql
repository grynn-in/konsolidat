{#
    Decision 13 (13 Sep 2026): each intercompany difference is labelled by its
    cause, and only a booking difference counts against the tolerance.

    1. currency: each side's currency is its entity's functional currency
       (silver_entity_currencies), the input the rule reads.
    2. cause: difference_cause follows the rule (see gold_ic_reconciliation):
       none below materiality_floor(); fx across currencies; booking in one currency when
       the local amounts do not net to zero; fx in one currency when they do
       (translation only). The local amounts are recomputed from
       gold_consolidated_trial_balance (ic_expected_pair_values), not taken
       from the model's own columns (#175 re-review L4).
    3. status: an fx difference is 'fx_difference' and never counts against
       the tolerance. A booking difference is within_tolerance or
       over_tolerance against the group's tolerance.
    4. label: each 'difference' elimination row carries its pair's cause, so
       splitting the difference account in two later needs no data change.
#}

with expected as (
    {{ ic_expected_pair_values() }}
),

rec as (
    select
        r.*,
        multiIf(
            abs(r.difference) < {{ materiality_floor() }}, 'none',
            r.currency_a != r.currency_b, 'fx',
            abs(e.expected_local_a + e.expected_local_b) >= {{ materiality_floor() }}, 'booking',
            'fx'
        ) as expected_cause
    from {{ ref('gold_ic_reconciliation') }} as r
    left join expected as e
        on e.consolidation_group = r.consolidation_group and e.fiscal_year = r.fiscal_year
        and e.fiscal_period = r.fiscal_period and e.entity_a = r.entity_a and e.account_a = r.account_a
        and e.entity_b = r.entity_b and e.account_b = r.account_b
),

currencies as (
    select data_area_id as currency_entity, any(accounting_currency) as functional_currency
    from {{ ref('silver_entity_currencies') }}
    group by data_area_id
),

currency_check as (
    select
        'currency' as failed_check, r.consolidation_group as consolidation_group,
        r.fiscal_year as fiscal_year, r.fiscal_period as fiscal_period,
        concat(r.entity_a, ' ', r.currency_a, ' / ', r.entity_b, ' ', r.currency_b) as detail,
        concat(ca.functional_currency, ' / ', cb.functional_currency) as expected
    from rec as r
    left join currencies as ca on ca.currency_entity = r.entity_a
    left join currencies as cb on cb.currency_entity = r.entity_b
    where r.currency_a != ca.functional_currency or r.currency_b != cb.functional_currency
),

cause_check as (
    select
        'cause' as failed_check, consolidation_group, fiscal_year, fiscal_period,
        concat(entity_a, '/', account_a, ' <> ', entity_b, '/', account_b, ': ', difference_cause) as detail,
        expected_cause as expected
    from rec
    where difference_cause != expected_cause
),

status_check as (
    select
        'status' as failed_check, consolidation_group, fiscal_year, fiscal_period,
        concat(entity_a, '/', account_a, ' <> ', entity_b, '/', account_b, ': ', match_status) as detail,
        multiIf(
            expected_cause = 'none', 'matched',
            expected_cause = 'fx', 'fx_difference',
            abs(difference) <= tolerance, 'within_tolerance',
            'over_tolerance'
        ) as expected
    from rec
    where match_status != multiIf(
            expected_cause = 'none', 'matched',
            expected_cause = 'fx', 'fx_difference',
            abs(difference) <= tolerance, 'within_tolerance',
            'over_tolerance')
       or (difference_cause = 'fx' and match_status = 'over_tolerance')
),

label_check as (
    select
        'label' as failed_check, e.consolidation_group as consolidation_group,
        e.fiscal_year as fiscal_year, e.fiscal_period as fiscal_period,
        concat(e.rule_id, ': ', e.difference_cause) as detail,
        r.difference_cause as expected
    from {{ ref('gold_ic_eliminations') }} as e
    left join rec as r
        on r.consolidation_group = e.consolidation_group and r.fiscal_year = e.fiscal_year
        and r.fiscal_period = e.fiscal_period and r.entity_a = e.entity_a and r.account_a = e.account_a
        and r.entity_b = e.entity_b and r.account_b = e.account_b
    where e.elimination_kind = 'difference'
      {# a reversal, posted once a balance-sheet pair agrees again, carries the
         cause of the difference it reverses #}
      and (e.difference_cause not in ('booking', 'fx')
           or (e.difference_cause != r.difference_cause and r.difference_cause != 'none'))
)

select * from currency_check
union all
select * from cause_check
union all
select * from status_check
union all
select * from label_check
