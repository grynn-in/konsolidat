-- konsol#117 pair 2 K2 (konsolidat#204 option (a), IFRS 10.B94): every NCI attribution journal sums to zero.
-- Retained earnings, CTA and the NCI account take the result and CTA the minority owns out of the
-- group's equity lines and into the NCI line, so no journal may leave a residual.
-- Fixture: dbt_project/test_fixtures/nci_attribution_journal.sql.
{{ config(severity='error') }}
select
    journal_id,
    sum(amount) as journal_total
from {{ ref('gold_nci_attribution_journal') }}
group by journal_id
having abs(sum(amount)) > 0.01
