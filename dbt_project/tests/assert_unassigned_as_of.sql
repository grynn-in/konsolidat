{# konsolidat#220: a dimension value is unassigned in a period only when no leaf tranche of the default
   hierarchy covers that period. On the fixture hierarchy_dated.sql (ZZ_DIV over dim_business_unit, entity ZZE1):
     - ZZ_ZX is a leaf only from 2025-01-01, so it is unassigned in FY2024 P6 and not in FY2025 P6;
     - ZZ_EX is a leaf in every period it has actuals (under ZZ_E to 2024, under ZZ_B from 2025): never unassigned.
   Guards: the fixture must reach gold_trial_balance with ZZ_ZX in FY2025 and ZZ_EX, or the "not unassigned"
   checks pass vacuously. One row per broken expectation.

   A model without fiscal_year / fiscal_period is read as "unassigned in every period" (fy = 0), so the checks
   fail on their merits rather than with a missing-column error. #}

-- depends_on: {{ ref('gold_unassigned_hierarchy_members') }}
{% set has_period = false %}
{% if execute %}
    {% set cols = adapter.get_columns_in_relation(ref('gold_unassigned_hierarchy_members')) | map(attribute='name') | list %}
    {% set has_period = ('fiscal_year' in cols and 'fiscal_period' in cols) %}
{% endif %}

with u as (
    select
        dimension_member_code as code,
        {% if has_period %}
        toInt32(fiscal_year) as fy,
        toInt32(fiscal_period) as fp
        {% else %}
        toInt32(0) as fy,
        toInt32(0) as fp
        {% endif %}
    from {{ ref('gold_unassigned_hierarchy_members') }}
    where hierarchy_dimension = 'dim_business_unit'
      and default_hierarchy_name = 'ZZ_DIV'
      and dimension_member_code in ('ZZ_ZX', 'ZZ_EX')
),

tb as (
    select
        dim_business_unit as code,
        toInt32(fiscal_year) as fy,
        toInt32(fiscal_period) as fp
    from {{ ref('gold_trial_balance') }}
    where data_area_id = 'ZZE1'
      and dim_business_unit in ('ZZ_ZX', 'ZZ_EX')
    group by code, fy, fp
),

zx_2024 as (
    select count() as n from u where code = 'ZZ_ZX' and (fy = 0 or (fy = 2024 and fp = 6))
)

-- ZZ_ZX has no leaf tranche in FY2024: it must be reported unassigned there
select
    'FY2024 P6 ZZ_ZX' as member,
    'not reported unassigned (no leaf tranche covers 2024-06-30)' as problem
from zx_2024
where n = 0

union all

-- ZZ_ZX is a leaf from 2025, ZZ_EX always: neither may be unassigned in a period its leaf tranche covers
select
    concat(if(fy = 0, 'every period', concat('FY', toString(fy), ' P', toString(fp))), ' ', code) as member,
    'reported unassigned, but a leaf tranche covers the period' as problem
from u
where code = 'ZZ_EX'
   or (code = 'ZZ_ZX' and (fy = 0 or fy >= 2025))

union all

-- guards: the fixture's actuals must reach the trial balance
select
    concat('FY', toString(e.fy), ' P', toString(e.fp), ' ', e.code) as member,
    'no trial-balance row for this member and period (fixture did not reach gold_trial_balance)' as problem
from (
    select 'ZZ_ZX' as code, toInt32(2025) as fy, toInt32(6) as fp
    union all select 'ZZ_ZX', 2024, 6
    union all select 'ZZ_EX', 2018, 6
    union all select 'ZZ_EX', 2025, 6
) as e
where concat(e.code, '|', toString(e.fy), '|', toString(e.fp))
    not in (select concat(code, '|', toString(fy), '|', toString(fp)) from tb)
