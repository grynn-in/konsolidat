{#
    konsol#117 pair 3 K2 (IFRS 11.B34-B37): unrealised profit on intragroup inventory is eliminated to the
    extent of the operator's interest. Per unrealized_profit row of gold_ic_eliminations, the amount must equal
    ending_inventory_from_ic x margin_pct / 100 x least(share_seller, share_buyer), share = effective_ownership_pct
    where the entity is `proportional` in that group and period, else 1.0 (an entity with no ownership row there
    keeps 1.0; join_use_nulls=0 fills a miss with method '', which is not 'proportional'). The oracle reads the
    staging inputs and gold_entity_ownership, not the model's own factor. Returns the rows that differ. A LEFT JOIN from `expected`: a missing model row fills
    elimination_amount with 0 (join_use_nulls=0) and is flagged whenever expected > 0.
#}

with expected as (
    select
        icr.rule_id as rule_id,
        cg.consolidation_group as consolidation_group,
        icb.fiscal_year as fiscal_year,
        icb.fiscal_period as fiscal_period,
        icb.selling_entity as selling_entity,
        icb.buying_entity as buying_entity,
        toFloat64(icb.ending_inventory_from_ic) * (toFloat64(icr.margin_pct) / 100.0) * least(
            if(os.consolidation_method = 'proportional', toFloat64(os.effective_ownership_pct), 1.0),
            if(ob.consolidation_method = 'proportional', toFloat64(ob.effective_ownership_pct), 1.0)
        ) as expected_amount
    from {{ source('epm_staging', 'ic_elimination_rules') }} as icr
    cross join {{ source('epm_staging', 'ic_balances') }} as icb
    inner join (
        select distinct consolidation_group, data_area_id
        from {{ ref('gold_entity_ownership') }}
        where has_complete_chain = 1 and consolidation_method != 'equity'
    ) as cg on icb.buying_entity = cg.data_area_id
    left join {{ ref('gold_entity_ownership') }} as os
        on os.consolidation_group = cg.consolidation_group and os.data_area_id = icb.selling_entity
        and os.fiscal_year = icb.fiscal_year and os.fiscal_period = icb.fiscal_period
    left join {{ ref('gold_entity_ownership') }} as ob
        on ob.consolidation_group = cg.consolidation_group and ob.data_area_id = icb.buying_entity
        and ob.fiscal_year = icb.fiscal_year and ob.fiscal_period = icb.fiscal_period
    where icr.rule_type = 'unrealized_profit'
      and icb.ending_inventory_from_ic > 0
      and icr.margin_pct > 0
      and (icr.debit_entity_pattern = '*' or icb.selling_entity = icr.debit_entity_pattern)
      and (icr.credit_entity_pattern = '*' or icb.buying_entity = icr.credit_entity_pattern)
)

select
    e.consolidation_group, e.fiscal_year, e.fiscal_period, e.selling_entity, e.buying_entity,
    e.expected_amount, toFloat64(m.elimination_amount) as elimination_amount
from expected as e
left join {{ ref('gold_ic_eliminations') }} as m
    on m.rule_id = e.rule_id and m.consolidation_group = e.consolidation_group
    and m.fiscal_year = e.fiscal_year and m.fiscal_period = e.fiscal_period
    and m.debit_entity = e.selling_entity and m.credit_entity = e.buying_entity
    and m.rule_type = 'unrealized_profit'
where abs(toFloat64(m.elimination_amount) - e.expected_amount) > 0.01
