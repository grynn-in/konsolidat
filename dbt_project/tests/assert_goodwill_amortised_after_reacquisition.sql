-- konsolidat#335 review F5: under goodwill_treatment 'Amortise' every deal that booked goodwill
-- posts its first instalment, whatever exit or disposal the entity had BEFORE the deal. An exit
-- or disposal stops only the schedules of deals acquired before it (a re-acquisition starts a new
-- schedule). A row here is a deal of an Amortise group with goodwill and no amortisation journal.
-- Fixture: test_fixtures/assert_exit_derecognises_carried.amortise_reacquired.sql.
with policy as (
    select consolidation_group
    from {{ source('epm_gold', 'consolidation_groups') }}
    where data_area_id = ''
    group by consolidation_group
    having any(goodwill_treatment) = 'Amortise' and any(goodwill_amortisation_years) > 0
),

deals as (
    select deal, consolidation_group, data_area_id, sum(adjustment_amount) as goodwill
    from {{ ref('gold_business_combination_journal') }}
    where account_role = 'goodwill'
    group by deal, consolidation_group, data_area_id
    having sum(adjustment_amount) > {{ materiality_floor() }}
),

posted as (
    select deal, count() as lines
    from {{ ref('gold_goodwill_amortisation_journal') }}
    group by deal
)

select d.deal as deal, d.consolidation_group as consolidation_group, d.data_area_id as data_area_id, d.goodwill as goodwill
from deals as d
where d.consolidation_group in (select consolidation_group from policy)
  and d.deal not in (select deal from posted)
