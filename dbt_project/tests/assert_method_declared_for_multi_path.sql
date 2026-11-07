{#
    konsol#117 (design section 2): when a group reaches an entity along several
    paths and the links do not settle the method — their weakest-link methods
    disagree, or no path is all-`full` and the paths sum past
    DECLARATION_TRIGGER_PCT (50%, the IFRS 10.B35 presumption of control) — the
    group must DECLARE the method (Consolidation Method Declaration on the group
    node, synced to epm_staging.consolidation_method_declarations). The macro
    resolves such a row as method_source = 'undeclared' and consolidation_method
    'none', so nothing consolidates for (group, entity); this test fails the
    build naming the group, the entity, the period, the sum and the paths.

    The percentage decides nothing here: 60% held as two 30% equity stakes may be
    joint control (IFRS 11) or control (IFRS 10); only the group can say.

    Fixtures: assert_method_declared_for_multi_path.undeclared.must_flag.sql (flags 1),
    .declared_full.sql and .declared_equity.sql (pass).
#}

with paths as (
    select
        consolidation_group,
        data_area_id,
        arraySort(groupUniqArray(path_id)) as path_ids
    from {{ source('epm_staging', 'consolidation_ancestry') }}
    where consolidation_group != '' and data_area_id != ''
    group by consolidation_group, data_area_id
)

select
    eo.consolidation_group,
    eo.data_area_id,
    eo.fiscal_year,
    eo.fiscal_period,
    eo.effective_ownership_pct,
    eo.path_count,
    p.path_ids as paths,
    concat(
        'Group ', eo.consolidation_group, ' reaches ', eo.data_area_id, ' along ',
        toString(eo.path_count), ' paths (', arrayStringConcat(p.path_ids, '; '), ') summing to ',
        toString(round(eo.effective_ownership_pct * 100, 2)), '% in FY', toString(eo.fiscal_year),
        ' P', toString(eo.fiscal_period),
        ': the links do not settle the consolidation method. Declare it on the group ',
        '(Consolidation Method Declaration, konsol#117); until then nothing of ', eo.data_area_id,
        ' consolidates into ', eo.consolidation_group, '.'
    ) as message
from {{ ref('gold_entity_ownership') }} as eo
left join paths as p
    on p.consolidation_group = eo.consolidation_group
    and p.data_area_id = eo.data_area_id
where eo.method_source = 'undeclared'
