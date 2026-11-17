{{
    config(
        materialized='table',
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# konsolidat#335, option A (decided 14 Nov 2026 by Deepak Pai): the exit events of macros/ownership_exits(),
   materialised once. The macro is the rule (its header); this model only stores its rows.

   Why a model (task X22): ClickHouse inlines a WITH subquery at every reference, and the macro is the
   ownership graph on a period spine of declared_periods(). gold_ownership_exit_journal referenced it through
   chained CTEs 18 times; on an empty site its INSERT took 1.5-2.5 min and 1.44 GiB, and the server was
   OOM-killed in the TB-only first build. The readers that build (gold_ownership_exit_journal,
   gold_goodwill_amortisation_journal, consolidation_core's spine_stints for gold_consolidated_trial_balance)
   and assert_exit_accounts_declared ref this model, so the graph is resolved once per build. So do
   assert_exit_derecognises_carried, assert_exit_matches_ic_left, assert_exit_out_of_scope_named and
   assert_reentry_carries_full_balance (task X23): every fixture of theirs builds this model. Two readers keep the
   macro because a fixture of theirs runs in test mode on seeded sources and builds nothing:
   assert_ownership_exit_events (it tests the macro itself) and assert_bs_translated_at_closing_rate (its
   .must_flag fixture runs the test alone on a seeded CTB). A test-mode fixture of a reader of this model would
   see it cloned EMPTY, or ERROR where the warehouse lacks it: such a fixture declares `-- gate: build
   gold_ownership_exits <test>`.

   It reads sources only (ownership periods, ancestry, method declarations, business disposals, the fiscal
   calendar), so it has no model parent and sorts before every reader. Domain actuals: the actuals scope
   rebuilds gold_consolidated_trial_balance with a tag-only selector, so the events it reads must be in the
   same tag; the consolidation and reporting scopes select their upstream (+tag) and reach it too.

   One row per exit event, the macro's columns: consolidation_group, data_area_id, fiscal_year, fiscal_period
   (P, the exit period), out_fiscal_year, out_fiscal_period (F), previous_fiscal_year, previous_fiscal_period,
   method_before, share_before, end_date. #}

select
    x.consolidation_group as consolidation_group,
    x.data_area_id as data_area_id,
    x.fiscal_year as fiscal_year,
    x.fiscal_period as fiscal_period,
    x.out_fiscal_year as out_fiscal_year,
    x.out_fiscal_period as out_fiscal_period,
    x.previous_fiscal_year as previous_fiscal_year,
    x.previous_fiscal_period as previous_fiscal_period,
    x.method_before as method_before,
    x.share_before as share_before,
    x.end_date as end_date
from {{ ownership_exits() }} as x
