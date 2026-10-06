{#
    PRD-22: each consolidation layer must be present in the fully consolidated
    TB wherever it applies. One row per (consolidation_group, missing_layer).

    Decided by Deepak Pai, 6 Oct 2026: konsolidat#238 option #238-1, at error
    severity. The test used to expect all four layers unconditionally. Live has
    no declared intercompany account and no approved top-side journal, so it
    then failed on correct data. Rejected: #238-2 (warn and keep asserting all
    four: a permanent false warning) and #238-3 (delete the test: IC
    elimination would be asserted by nothing).

    "Applies" reads the same inputs the layer-building models read, per group:
      - entity: the group has rows in gold_consolidated_trial_balance, which
        layer 1 of gold_fully_consolidated_tb sums. (An empty warehouse has
        no group and so nothing to assert.)
      - ic_elimination: the group has a gold_consolidated_trial_balance row
        on a declared intercompany account (ic_account_map(), the Published
        rows of epm_staging.intercompany_accounts) whose partner is another
        entity. That is the `sides` CTE of gold_ic_reconciliation, which feeds
        gold_ic_eliminations. Accepted trade-off: a group that never declares
        its intercompany accounts passes; partner rows on undeclared accounts
        are konsol#317's to report.
      - topside: gold_consolidation_adjustments, the model layer 4 reads, has
        an adjustment_type 'topside' line for the group. The model keeps only
        Approved and Reversed journals.
      - cta: the group's entities in gold_consolidated_trial_balance carry
        more than one accounting (functional) currency.

    konsolidat#238 / #249: NOT IN, not a LEFT JOIN. adjustment_type is a
    String, and under join_use_nulls = 0 (the server default; a singular test
    carries no settings clause) an unmatched LEFT JOIN fills it with '' rather
    than NULL. The former `where actual.layer is null` therefore matched
    nothing, and the test could never fail.
#}

with applies as (

    select consolidation_group, 'entity' as layer
    from {{ ref('gold_consolidated_trial_balance') }}
    group by consolidation_group

    union all

    select distinct ctb.consolidation_group, 'ic_elimination' as layer
    from {{ ref('gold_consolidated_trial_balance') }} as ctb
    inner join ({{ ic_account_map() }}) as ica
        on ctb.main_account = ica.account
    where ctb.partner_data_area_id != ''
      and ctb.partner_data_area_id != ctb.data_area_id

    union all

    select consolidation_group, 'cta' as layer
    from {{ ref('gold_consolidated_trial_balance') }}
    group by consolidation_group
    having uniqExact(accounting_currency) > 1

    union all

    select distinct consolidation_group, 'topside' as layer
    from {{ ref('gold_consolidation_adjustments') }}
    where adjustment_type = 'topside'

)

select
    'missing_layer' as error,
    consolidation_group,
    layer as missing_layer
from applies
where (consolidation_group, layer) not in (
    select distinct consolidation_group, adjustment_type
    from {{ ref('gold_fully_consolidated_tb') }}
)
