{#
    konsol#182: the group chart of accounts governed in konsol (Main Account,
    written through to epm_staging.main_accounts on publish). It is
    silver_main_accounts' only source.
#}

{# The governed chart's relation, or none when the table does not exist yet (a
   volume konsol has not upgraded). This is what lets this project deploy
   before konsol creates the table: no table reads as no declarations, and
   silver is empty with its full set of columns. Callers that read the table
   also carry a `-- depends_on:` on the source, because nothing is resolved at
   parse time. #}
{% macro governed_chart_relation() %}
    {%- if not execute -%}
        {{ return(none) }}
    {%- endif -%}
    {%- set s = source('epm_staging', 'main_accounts') -%}
    {{ return(adapter.get_relation(database=none, schema=s.schema, identifier=s.identifier)) }}
{% endmacro %}

{# One row per (main_account, problem) that silver cannot use. Published rows
   only; konsol validates on save, so a row here means the table was written
   around konsol, or two syncs raced:
     (a) duplicate Published rows for one code that differ in ANY declared
         column, named (two concurrent TRUNCATE+INSERT syncs can double a row;
         identical duplicates are harmless and collapse in silver, but a
         disagreeing pair has no right answer to pick);
     (b) a Published leaf whose statement_section or fx_method is outside the
         vocabulary, so it would land in neither statement or be translated
         at no rate;
     (c) a P&L account at the historical rate, or a balance-sheet account at
         the average rate.
   Empty when the table does not exist. #}
{% macro governed_chart_problems() %}
{%- set rel = governed_chart_relation() -%}
{#- every column of epm_staging.main_accounts but status (constant here: the
    rows are Published). tests/test_governed_chart_ddl.py holds this list to
    the DDL, so a column added there cannot escape the comparison. -#}
{%- set _declared = ['account_name', 'chart_of_accounts', 'parent_account', 'is_group', 'account_type',
                     'statement_section', 'sub_section', 'normal_balance', 'time_balance', 'fx_method',
                     'is_posting', 'is_suspended', 'allow_ic', 'cf_category', 'cf_line_item', 'is_cash',
                     'main_account_category', 'is_retained_earnings'] -%}
{%- if rel is none -%}
select '' as main_account, '' as problem where 0
{%- else -%}
{#- konsolidat#199: the two repos deploy in either order, so a declared column
    the table does not have yet (is_retained_earnings until konsol row K7 has
    migrated) is left out of the comparison instead of breaking the query. -#}
{%- set _present = adapter.get_columns_in_relation(rel) | map(attribute='name') | list -%}
{%- set _compared = _declared | select('in', _present) | list -%}
select main_account, problem from (
    select
        main_account,
        concat('duplicate Published rows disagree on ', arrayStringConcat(arrayFilter(c -> c != '', [
            {%- for c in _compared %}
            if(uniqExact({{ c }}) > 1, '{{ c }}', ''){{ ',' if not loop.last }}
            {%- endfor %}
        ]), ', ')) as problem
    from {{ rel }}
    where status = 'Published'
    group by main_account
    having uniqExact(tuple({{ _compared | join(', ') }})) > 1

    union all

    select
        main_account,
        concat('statement_section [', statement_section, '] is neither Profit and Loss nor Balance Sheet') as problem
    from {{ rel }}
    where status = 'Published' and is_group = 0
      and statement_section not in ('Profit and Loss', 'Balance Sheet')

    union all

    select
        main_account,
        concat('fx_method [', fx_method, '] is not closing, average or historical') as problem
    from {{ rel }}
    where status = 'Published' and is_group = 0
      and fx_method not in ('closing', 'average', 'historical')

    union all

    select
        main_account,
        concat(statement_section, ' at the ', fx_method, ' rate (P&L translates at average or closing, the balance sheet at closing or historical)') as problem
    from {{ rel }}
    where status = 'Published' and is_group = 0
      and ((statement_section = 'Profit and Loss' and fx_method = 'historical')
        or (statement_section = 'Balance Sheet' and fx_method = 'average'))
)
{%- endif -%}
{% endmacro %}

{# silver_main_accounts' pre_hook, in the governed_rate_guard shape: stops the
   build before the table is replaced, naming the first 50 problems sorted
   (assert_governed_chart_declarations_usable lists all). ClickHouse's throwIf
   needs a constant message; a CAST of the message to UInt8 raises with the
   message itself in the error. The inner query always returns one row; the
   outer WHERE keeps it only when there is something to refuse, so the CAST is
   never evaluated on a clean run. #}
{% macro governed_chart_guard() %}
{%- set rel = governed_chart_relation() -%}
{%- if rel is none -%}
select 1
{%- else -%}
select cast(concat(
    'konsol#182 refused before silver_main_accounts was replaced: ', toString(n),
    ' unusable declaration(s) in the governed chart (konsol Main Account, epm_staging.main_accounts): ', keys,
    if(n > 50, concat(' ... and ', toString(n - 50), ' more (assert_governed_chart_declarations_usable lists all)'), ''),
    '. Correct or unpublish them in konsol, then rebuild.'
) as UInt8)
from (
    select
        count() as n,
        arrayStringConcat(arraySlice(arraySort(groupArray(concat(main_account, ': ', problem))), 1, 50), '; ') as keys
    from ({{ governed_chart_problems() }})
)
where n > 0
{%- endif -%}
{% endmacro %}
