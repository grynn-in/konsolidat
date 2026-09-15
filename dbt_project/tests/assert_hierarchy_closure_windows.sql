{# konsolidat#220: every closure link holds only within a window (valid_from .. valid_to), the intersection of
   the member tranches along the path, and carries the ancestor tranche's label for that window.
   On the fixture hierarchy_dated.sql (ZZ_DIV):
     - ZZ_EX -> ZZ_E holds only within 2017-01-01 .. 2024-12-31;
     - ZZ_EX -> ZZ_B holds only from 2025-01-01;
     - ZZ_GX -> ZZ_G holds only within 2013-04-01 .. 2020-06-03;
     - ZZ_AX -> ZZ_A is labelled "Alpha" before 2025 and "Alpha New" from 2025;
     - no closure row has valid_from > valid_to.
   One row per broken expectation.

   A closure without the window columns is read as "every link holds always" (1900-01-01 .. 2999-12-31), so
   the checks fail on their merits rather than with a missing-column error. #}

-- depends_on: {{ ref('gold_reporting_hierarchy_closure') }}
{% set has_window = false %}
{% if execute %}
    {% set cols = adapter.get_columns_in_relation(ref('gold_reporting_hierarchy_closure')) | map(attribute='name') | list %}
    {% set has_window = ('valid_from' in cols and 'valid_to' in cols) %}
{% endif %}

with c as (
    select
        descendant_member_code,
        ancestor_member_code,
        ancestor_label,
        {% if has_window %}
        valid_from,
        valid_to
        {% else %}
        toDate('1900-01-01') as valid_from,
        toDate('2999-12-31') as valid_to
        {% endif %}
    from {{ ref('gold_reporting_hierarchy_closure') }}
    where hierarchy_name = 'ZZ_DIV'
),

expectations as (
    -- (descendant, ancestor, label or '' for any, earliest allowed valid_from, latest allowed valid_to)
    select 'ZZ_EX' as d, 'ZZ_E' as a, '' as lbl, toDate('2017-01-01') as lo, toDate('2024-12-31') as hi
    union all select 'ZZ_EX', 'ZZ_B', '', toDate('2025-01-01'), toDate('2999-12-31')
    union all select 'ZZ_GX', 'ZZ_G', '', toDate('2013-04-01'), toDate('2020-06-03')
    union all select 'ZZ_AX', 'ZZ_A', 'Alpha', toDate('1900-01-01'), toDate('2024-12-31')
    union all select 'ZZ_AX', 'ZZ_A', 'Alpha New', toDate('2025-01-01'), toDate('2999-12-31')
)

-- a link that holds outside its window
select
    concat(c.descendant_member_code, ' -> ', c.ancestor_member_code, ' "', c.ancestor_label, '"') as link,
    concat('holds ', toString(c.valid_from), ' .. ', toString(c.valid_to),
           ', allowed ', toString(e.lo), ' .. ', toString(e.hi)) as problem
from c
inner join expectations as e
    on e.d = c.descendant_member_code
    and e.a = c.ancestor_member_code
where (e.lbl = '' or e.lbl = c.ancestor_label)
  and (c.valid_from < e.lo or c.valid_to > e.hi)

union all

-- an expected link that is missing altogether
select
    concat(e.d, ' -> ', e.a, ' "', e.lbl, '"') as link,
    'missing' as problem
from expectations as e
where concat(e.d, '|', e.a, '|', e.lbl) not in (
    select concat(descendant_member_code, '|', ancestor_member_code, '|', ancestor_label) from c
    union all
    select concat(descendant_member_code, '|', ancestor_member_code, '|') from c
)

union all

-- an empty window
select
    concat(descendant_member_code, ' -> ', ancestor_member_code) as link,
    concat('valid_from ', toString(valid_from), ' > valid_to ', toString(valid_to)) as problem
from c
where valid_from > valid_to
