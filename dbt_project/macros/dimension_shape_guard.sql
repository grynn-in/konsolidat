{#
    konsol#287 review: no silent reshape of a site's dimension columns.

    konsolidat ships `dimensions: []`; konsol writes the site's own declaration
    into dbt_project.yml on migrate. A `run` or `build` before that migrate (a
    stack that pulled the new file and was not migrated, a hand-run build on a
    fresh copy) would rebuild every dimensional model at the empty default and
    drop the site's dim_* columns, and the reports reading them, without a word.

    This on-run-start hook refuses that run. It compares the declared names,
    var('dimensions'), with the dimension columns the built gold_trial_balance
    already has (system.columns, as widen_amount_columns reads it). They are
    compared as sets: a declaration that only reorders the same dimensions
    reshapes nothing.

    Like with like. gold_trial_balance selects EVERY declared dimension
    (dim_select() with no filter; dbt has no trial-balance-only list), and
    var('dimensions') holds every Published Dimension, including a budget-only
    one konsol lets the site name without the dim_ prefix (konsol
    dimension.py validate: the prefix rule binds in_trial_balance only). So
    the built side is not "columns starting dim_" but every column of the
    table that is not one of its fixed columns (`fixed` below, from
    gold_trial_balance.sql's own select list) or a declared measure
    (var('base_measures')).

    It allows the run when:
      - gold_trial_balance does not exist yet (a fresh site or scratch schema:
        there is nothing to reshape);
      - --full-refresh is set (flags.FULL_REFRESH): the operator asked for the
        rebuild;
      - the command is not `run`, `build` or `retry` (dbt test, seed,
        snapshot never rebuild gold_trial_balance; compile and run-operation
        run no hooks). In dbt 1.12 `dbt retry` re-parses under the previous
        command's flags (task/retry.py), so flags.WHICH there reads `run` or
        `build` and the retry is checked; `retry` is listed for a dbt that
        reports the command itself.

    The relation is found in the graph, so a project copy whose schemas are
    rewritten (the fixture gate's zzg_*, scratch prefixes) checks its own.
#}
{% macro assert_dimensions_match_built() %}
    {%- if not execute or flags.FULL_REFRESH or flags.WHICH not in ('run', 'build', 'retry') -%}
        {{ return('select 1') }}
    {%- endif -%}
    {%- set tb = [] -%}
    {%- for node in graph.nodes.values() -%}
        {%- if node.resource_type == 'model' and node.name == 'gold_trial_balance' -%}
            {%- do tb.append(node) -%}
        {%- endif -%}
    {%- endfor -%}
    {%- if tb | length != 1 -%}
        {{ exceptions.raise_compiler_error(
            "assert_dimensions_match_built: expected one gold_trial_balance model in the graph, found "
            ~ (tb | length)) }}
    {%- endif -%}
    {%- set schema = tb[0].schema -%}
    {%- set identifier = tb[0].alias or tb[0].name -%}
    {%- set exists = run_query(
        "select count() from system.tables where database = '" ~ schema
        ~ "' and name = '" ~ identifier ~ "'").columns[0].values()[0] -%}
    {%- if exists | int == 0 -%}
        {{ return('select 1') }}
    {%- endif -%}
    {#- gold_trial_balance.sql's columns that are not dimensions or measures -#}
    {%- set fixed = ['data_area_id', 'fiscal_year', 'fiscal_period', 'main_account', 'account_name',
                     'account_type_name', 'is_balance_sheet', 'is_pnl']
                    + (var('base_measures', []) | map(attribute='name') | list) -%}
    {%- set built = [] -%}
    {%- for name in run_query(
        "select name from system.columns where database = '" ~ schema
        ~ "' and table = '" ~ identifier ~ "' order by name"
    ).columns[0].values() -%}
        {%- if name not in fixed -%}
            {%- do built.append(name) -%}
        {%- endif -%}
    {%- endfor -%}
    {%- set declared = get_dimensions() | map(attribute='name') | sort | list -%}
    {%- if (built | sort | list) != declared -%}
        {{ exceptions.raise_compiler_error(
            "konsol#287: refusing to reshape the dimension columns of " ~ schema ~ "." ~ identifier ~ ". "
            ~ "It was built with [" ~ ((built | join(', ')) or '(none)') ~ "]; this run declares ["
            ~ ((declared | join(', ')) or '(none)') ~ "] (var 'dimensions'). "
            ~ "If the site's dimensions have not changed, run konsol migrate (bench --site <site> migrate) "
            ~ "to regenerate the vars in dbt_project.yml, then build again. "
            ~ "If a Dimension was just published or unpublished, its full-refresh Build Approval is pending: "
            ~ "approve it (or wait for it) instead of migrating. "
            ~ "If the change is deliberate, pass --full-refresh to rebuild at the new declaration.") }}
    {%- endif -%}
    {{ return('select 1') }}
{% endmacro %}
