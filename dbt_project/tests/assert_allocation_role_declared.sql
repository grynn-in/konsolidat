{#
    konsolidat#220: allocation rules without a cost-centre dimension to apply them to.

    The allocation engine groups the trial balance by the dimension a site declares
    with `allocation_role: cost_center`. A site that declares none has nothing to
    allocate across, so the engine renders no rows — which is the correct answer for
    a site that does not allocate, and a silent one for a site that does.

    This test is the loud half of that decision (konsolidat#220, PR #222):
    it returns one row per Allocation Rule when rules exist while no published
    Dimension declares the role, so the close names the misconfiguration instead of
    reporting an empty allocation. When the role IS declared it asserts nothing —
    the engine's own assertions cover the numbers from there.

    Why not a compile-time error: measured 18 Sep, a raise_compiler_error in
    get_allocation_cost_center_dim() aborts dbt at PARSE time for the whole project
    (`dbt parse` and `dbt compile` both exit 2 at zero dimensions, even with
    `enabled=false` on the allocation models), so it would break every site that
    declares no dimensions — the case konsolidat#220 exists to fix.

    konsol#263 makes `allocation_role` a validated declaration, which is what
    catches a typo (`Cost Center`) on a site that has no rules yet.
#}

-- depends_on: {{ source('epm_staging', 'allocation_rules') }}
{% if get_allocation_cost_center_dim() == '' %}
select
    allocation_rule_id,
    rule_name,
    'allocation rule declared, but no published Dimension carries allocation_role: cost_center — the engine has no dimension to allocate across and produces no rows' as problem
from {{ source('epm_staging', 'allocation_rules') }}
{% else %}
select
    '' as allocation_rule_id,
    '' as rule_name,
    '' as problem
where 1 = 0
{% endif %}
