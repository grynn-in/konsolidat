-- konsol#305 V05 (batch review finding 2): gold_consolidation_journal is the audit trail the
-- 8.2 drill reads (E10), and it must name every journal it reports on. Before the fix, layer 4
-- of gold_fully_consolidated_tb sums topside/reclassification/auto_reversal lines to the account
-- grain and reports any(journal_id) for the group — one journal name survives when two journals
-- post to the same account in the same period (batch review 27 Sep finding 2: ZZJ-00001 and
-- ZZJ-00002 on one key became one row labelled with only one of them). This test returns every
-- journal_id present in gold_consolidation_adjustments (the topside/reclassification/
-- auto_reversal rows, none of them 'entity') that is absent from gold_consolidation_journal.
-- Fixture: dbt_project/test_fixtures/assert_journal_grain_unique.topside.sql (reused from V03,
-- not copied): ZZJ-00001 and ZZJ-00002, both Dr ZZ1100 / Cr ZZ2100, ZZG/ZZS FY2026 P3.
select distinct adj.journal_id
from {{ ref('gold_consolidation_adjustments') }} as adj
where adj.journal_id not in (
    select journal_id from {{ ref('gold_consolidation_journal') }}
)
