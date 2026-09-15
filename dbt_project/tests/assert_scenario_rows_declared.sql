{# PR #211 review 2 (konsolidat#206): every scenario_id in gold_scenario_trial_balance
   is an ACTIVE scenario declared in epm_gold.scenario_definitions with the
   scenario_type its branch needs. The variance models keep only active scenarios
   of the matching type, so rows under any other scenario (a site that marks
   ACTUAL inactive, or declares its own actual id) would silently drop out of
   variance; this test names them instead.

   Branch (data_source) -> accepted scenario_type:
     gl                    -> actual
     budget, d365_budget   -> budget or forecast

   One row per (scenario_id, data_source) with rows, problem one of:
     undeclared - no scenario_definitions row for the id;
     inactive   - declared, but no row with is_active = 1;
     wrong_type - active, but no active row has the branch's type. #}

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
