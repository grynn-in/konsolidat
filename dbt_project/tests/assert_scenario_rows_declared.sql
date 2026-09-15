{# PR #211 review 2 (konsolidat#206): the scenarios of gold_scenario_trial_balance
   are declared. This test checks declaration, activeness and branch type: every
   scenario_id with rows is an ACTIVE scenario in epm_gold.scenario_definitions
   whose scenario_type suits its branch, and the site declares at most one active
   actual scenario (the GL branch is stamped with it; with several it keeps the
   fallback 'ACTUAL').

   Branch (data_source) -> accepted scenario_type:
     gl                    -> actual
     budget, d365_budget   -> budget or forecast

   Forecasts are legitimate rows of the scenario trial balance, so the budget
   branches accept them here. The variance models read only 'budget'-type
   scenarios, so forecast rows never reach variance; that is by design, not a
   problem this test names.

   Problems:
     undeclared     - one row per (scenario_id, data_source) with rows: no
                      scenario_definitions row for the id;
     inactive       - declared, but no row with is_active = 1;
     wrong_type     - active, but no active row has the branch's type;
     several_actual - one row whenever more than one active 'actual' scenario is
                      declared, whatever the rows say: scenario_id lists the
                      active actual ids (sorted, comma-separated), data_source ''. #}

with tb_scenarios as (
    select
        scenario_id as t_scenario_id,
        data_source as t_data_source
    from {{ ref('gold_scenario_trial_balance') }}
    group by t_scenario_id, t_data_source
),

definitions as (
    select
        scenario_id as d_scenario_id,
        toUInt8(1) as d_declared,
        max(toUInt8(is_active = 1)) as d_any_active,
        groupUniqArrayIf(scenario_type, is_active = 1) as d_active_types
    from {{ source('epm_gold', 'scenario_definitions') }}
    group by d_scenario_id
),

checked as (
    select
        t.t_scenario_id as c_scenario_id,
        t.t_data_source as c_data_source,
        ifNull(d.d_declared, 0) as c_declared,
        ifNull(d.d_any_active, 0) as c_any_active,
        hasAny(
            d.d_active_types,
            multiIf(
                t.t_data_source = 'gl', ['actual'],
                t.t_data_source in ('budget', 'd365_budget'), ['budget', 'forecast'],
                emptyArrayString()
            )
        ) as c_type_ok
    from tb_scenarios as t
    left join definitions as d
        on t.t_scenario_id = d.d_scenario_id
),

active_actuals as (
    select
        arraySort(groupUniqArray(scenario_id)) as a_ids
    from {{ source('epm_gold', 'scenario_definitions') }}
    where scenario_type = 'actual'
      and is_active = 1
)

select
    c_scenario_id as scenario_id,
    c_data_source as data_source,
    multiIf(
        c_declared = 0, 'undeclared',
        c_any_active = 0, 'inactive',
        'wrong_type'
    ) as problem
from checked
where c_type_ok = 0

union all

select
    arrayStringConcat(a_ids, ',') as scenario_id,
    '' as data_source,
    'several_actual' as problem
from active_actuals
where length(a_ids) > 1
