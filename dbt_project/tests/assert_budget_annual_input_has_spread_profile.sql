-- konsol#525: every annual budget input names a Spread Profile that exists.
-- gold_spread_budget inner-joins epm_gold.spread_profiles on profile_id = spread_profile_id, so an
-- input whose spread_profile_id matches no profile has no row in the budget fact: the annual figure
-- is dropped without a word, and assert_spread_sums_to_annual passes because it reads only the fact.
-- Flags one row per input (the annual-input table is read, not the join, so a profile's several
-- periods cannot multiply a row). The match is exact, as the model's join is.
-- Error severity: a missing budget is a wrong budget. konsol refuses the value at intake; this is
-- the backstop for a row that reached the warehouse any other way.
-- join_use_nulls=0: the comparison uses NOT IN, never a LEFT JOIN.
{{ config(severity='error') }}

select
    scenario_id,
    data_area_id,
    fiscal_year,
    main_account,
    layer,
    spread_profile_id
from {{ source('epm_gold', 'budget_annual_input') }}
where spread_profile_id not in (
    select profile_id from {{ source('epm_gold', 'spread_profiles') }}
)
