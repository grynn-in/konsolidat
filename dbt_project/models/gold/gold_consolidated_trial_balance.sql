{{
    config(
        materialized='incremental',
        incremental_strategy='append',
        query_settings={'query_plan_enable_multithreading_after_window_functions': 0},
        pre_hook=[
            "{{ governed_rate_guard() }}",
            "{% if is_incremental() %}ALTER TABLE {{ this }} ADD COLUMN IF NOT EXISTS partner_data_area_id String DEFAULT ''{% endif %}",
            "{% if is_incremental() %}ALTER TABLE {{ this }} ADD COLUMN IF NOT EXISTS uses_historical_rate UInt8 DEFAULT 0{% endif %}",
            "{% if is_incremental() %}ALTER TABLE {{ this }} ADD COLUMN IF NOT EXISTS retranslation_amount Float64 DEFAULT 0{% endif %}",
            "{{ widen_amount_columns(['local_amount']) }}",
            "{% if is_incremental() %}DELETE FROM {{ this }} WHERE 1 = 1 {{ period_filter() }} {{ scope_filter() }}{% endif %}"
        ],
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# konsolidat#204 (a), konsol#117 pairs 2 and 3. A controlled subsidiary
   (consolidation_method 'full', IFRS 10.B86): group_amount is 100% of
   translated_amount; nci_amount is the minority's attribution (translated x
   (1 - ownership_pct)) that the NCI line in equity carries. A joint operation
   ('proportional', IFRS 11.20): group_amount is the operator's share
   (translated x ownership_pct) and nci_amount is 0, as nobody holds a minority
   in it. 'equity' and 'none' are not line-consolidated. Pinned by
   assert_group_equals_translated_for_full,
   assert_group_equals_translated_times_share_for_proportional,
   assert_nci_equals_translated_times_minority and
   assert_nci_zero_for_proportional. #}

{# #256: the widen_amount_columns pre_hook (macros/amount_scale.sql) runs before
   the DELETE and the append. A table built before #256 holds its amounts as
   Decimal(38, 2), and an append into it would cut a three-decimal amount (BHD,
   KWD) to two places, without an error. The hook widens those columns to
   amount_type() once; after that it finds nothing to widen and renders nothing. #}

{# The query_settings line (konsolidat PR "Fix the TB-only first build after
   #262"): `retranslated`, `close_pnl` and `closed` below are three window steps,
   one over the other. With ClickHouse's default
   query_plan_enable_multithreading_after_window_functions = 1, every window
   step fans its input out again by max_threads x the partitions, so the
   pipeline grew 8 -> 40 -> 1,600 -> 64,000 processors before reading a row
   (EXPLAIN PIPELINE, clickhouse-server 24.8, max_threads 4). Building it took
   the server's memory on the empty TB-only site: the CI job "first
   build on a fresh TB-only site" ran 48 minutes and never finished. With the
   setting at 0, each window step keeps its input's streams (40 at most). It
   does not change any result: it only decides how many threads run the rows
   after a window. konsolidat#369: necessary, not sufficient. On a warehouse
   where every table is empty the plan has no max_threads cap at all and the
   sort BEFORE each window scatters into the accumulated stream count (51
   threads here at max_threads 4, 163 at 8); the core's entity_tb anchors the
   plan on system.one so the cap holds. #}
{# konsolidat#93: the first pre_hook (macros/governed_rates.sql) raises when a
   currency this run translates has no approved governed rate, BEFORE the
   DELETE below, so a missing rate leaves the table as it was. The throwIf in
   `consolidated` stays as the second line of defence. #}
{# konsol#159: partner_data_area_id rides through from gold_trial_balance, so
   gold_ic_reconciliation can pair (entity, partner) with (partner, entity) on
   translated group amounts.

   A pre_hook (after the rate guard, before the DELETE) adds it to a table built
   before it existed. dbt-clickhouse's append inserts POSITIONALLY into the
   target's columns and applies no on_schema_change on this path, so the new
   column must sit where ALTER ... ADD COLUMN puts it: at the end. Anywhere
   else every later column would land one place off, silently. #}
{# konsolidat#213: uses_historical_rate follows the same rule, and its ALTER runs
   after partner_data_area_id's — so the table's last two columns are
   partner_data_area_id, then uses_historical_rate, and the final select below
   emits them in exactly that order. Any further column goes after both. #}
{# konsolidat#257: retranslation_amount is that further column. Its ALTER runs
   third, so the table ends partner_data_area_id, uses_historical_rate,
   retranslation_amount, and the final select emits them in that order. #}

{# #154: delete the run's WHOLE scope, then append. delete+insert deleted only
   the keys the new batch produced, so a key that left the SELECT (an ownership
   window ending, a currency that stopped resolving, a method change) kept its
   last rows forever. No vars => no predicate => the whole table is replaced.
   An entity removed from the group tree is outside scope_filter, so only the
   next unscoped build clears it. #}

{# A2 / grynn-in/konsolidat#116: incremental-by-period materialization.
   This is the consolidation CHOKEPOINT, so a scoped orchestrator close
   (entity_scope / fiscal_year[ / fiscal_period] vars) narrows the SELECT to its
   slice. With delete+insert keyed on the close slice
   (consolidation_group, data_area_id, fiscal_year, fiscal_period) a scoped run
   replaces ONLY its slice and leaves every other slice intact, instead of
   OVERWRITING the whole table. The pre_hook above deletes the slice with the
   same filters the SELECT uses; the SELECT then appends it. `dbt --full-refresh`
   (or the first build) drops + recreates the table from scratch. #}

{# PRD-1: Proper FX translation — closing rate for BS, average rate for PnL,
          from the governed group rates only (konsolidat#93 / konsol#103).
   FX CONTRACT (13 Sep 2026): epm_staging.group_exchange_rates.rate is the true
   rate (units of to_currency per 1 from_currency), published by konsol, the
   single source of FX rates. The warehouse never scales or inverts it.
   konsol#348 (S4-Q1 c): a rate belongs to one Rate Set; the actuals read the
   one set flagged Is Actuals, and nothing else.
   silver_exchange_rates holds the ERP quotes, which feed only konsol's
   pre-fill.
   PRD-4: Minority interest — nci_amount column for partial ownership
   PRD-8: Multi-level hierarchy — effective_ownership from hierarchy or seed fallback
   PRD-9: Temporal ownership — period-level ownership from ownership_periods staging
   PRD-10: Historical equity rates — equity accounts use historical rate (IAS 21) #}

{# konsol#348 S4 (W3): the core (entity_tb .. consolidated) is
   macros/consolidation_core.sql, shared with the consolidated budget model.
   This model keeps what is its own: the incremental config and pre_hooks, the
   source CTE below (the partner trial balance, its signed movement, the
   statement flags from the row itself: S4-Q6 (a)), the actuals' dimensions,
   the materialised gold_entity_ownership, no extra grain, the scoped build,
   and the final positional select. The rate predicate is the actuals' (W2,
   S4-Q1 c / S4-Q7 a): both rate tables are read for the one Rate Set flagged
   is_actuals in epm_staging.rate_sets, the same set the pre_hook guard and
   assert_every_translated_currency_has_a_governed_rate judge; a budget's
   rates in the same tables are never read here
   (assert_translation_rates_are_the_actuals_sets). #}

with entity_tb_source as (
    select
        data_area_id,
        fiscal_year,
        fiscal_period,
        main_account,
        account_name,
        account_type_name,
        is_balance_sheet,
        is_pnl,
        partner_data_area_id,
        {{ dim_select(trailing=true) }}
        {# Signed double-entry movement (debit - credit), so the local TB sums
           to zero and the FX/CTA plug can balance it. Amounts arrive signed at
           the ERP boundary (models/staging/README.md). Silver splits them once
           into debit_amount / credit_amount by sign, and nothing after that
           infers a sign again. period_net_amount holds the same number
           (sum(debit) - sum(credit), per assert_period_net_equals_debit_minus_credit).
           It is no longer the positive magnitude #64 described. #}
        period_debit - period_credit as local_amount,
        is_year_end_close
    {# konsol#159: the partner-grained twin of gold_trial_balance. That model
       stays at the account grain for its own readers; see
       gold_trial_balance_by_partner. #}
    from {{ ref('gold_trial_balance_by_partner') }}
),

{# The pre_hook guard also reads the currencies' reference magnitudes and the
   fiscal calendar; declared here so dbt knows the dependencies at parse time. #}
-- depends_on: {{ source('epm_gold', 'currencies') }} {{ source('epm_staging', 'fiscal_periods') }}
{{ consolidation_core(source_cte='entity_tb_source',
                      dims=get_dimensions(),
                      rate_set_predicate=actuals_rate_set_predicate(),
                      ownership_cte=ref('gold_entity_ownership'),
                      grain_extra=[],
                      scoped=true,
                      exits_relation=ref('gold_ownership_exits')) }}

{# partner_data_area_id, then uses_historical_rate, then retranslation_amount,
   last: see the notes at the top. Each was added to an already-built table by
   an ALTER in the pre_hook, in that order, and ALTER ... ADD COLUMN appends at
   the end — so the select has to emit them in the same order or the
   positional append lands them swapped.
   konsolidat#257: the run's period filter applies here, after the windows. #}
select * except (partner_data_area_id, uses_historical_rate, translation_adjustment, fx_method,
                 is_retained_earnings, is_year_end_close, is_filler),
       partner_data_area_id,
       uses_historical_rate,
       {# konsolidat#259: the column also carries the year-end close's
          adjustment on P&L and retained-earnings close rows #}
       translation_adjustment as retranslation_amount
from consolidated
where 1 = 1
    {{ period_filter() }}
