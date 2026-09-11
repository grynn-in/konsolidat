{{
    config(
        query_settings={'allow_experimental_join_condition': 1},
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# IC elimination: find matching debit/credit account balances between entities
   and create offsetting entries
   PRD-15: Enhanced with unrealized profit elimination (rule_type = 'unrealized_profit') #}

{# PRD-15: IC elimination rules — prefer staging if populated, else seed #}
with ic_rules as (
    select
        rule_id,
        rule_name,
        debit_account,
        credit_account,
        debit_entity_pattern,
        credit_entity_pattern,
        'balance' as rule_type,
        toDecimal64(0, 2) as margin_pct,
        '' as asset_account
    from {{ ref('ic_elimination_rules') }}
    where not exists (
        select 1 from {{ source('epm_staging', 'ic_elimination_rules') }}
        where rule_id != ''
        limit 1
    )

    union all

    select
        rule_id,
        rule_name,
        debit_account,
        credit_account,
        debit_entity_pattern,
        credit_entity_pattern,
        rule_type,
        margin_pct,
        asset_account
    from {{ source('epm_staging', 'ic_elimination_rules') }}
),

{# Balance-based elimination: existing logic using ic_rules CTE #}
ic_balances as (
    select
        ctb.consolidation_group as consolidation_group,
        ctb.fiscal_year as fiscal_year,
        ctb.fiscal_period as fiscal_period,
        ctb.main_account as main_account,
        ctb.data_area_id as data_area_id,
        sum(ctb.group_amount) as account_balance
    from {{ ref('gold_consolidated_trial_balance') }} as ctb
    inner join (
        select debit_account as ic_account from ic_rules where rule_type = 'balance'
        union distinct
        select credit_account as ic_account from ic_rules where rule_type = 'balance'
    ) as ica
        on ctb.main_account = ica.ic_account
    group by
        ctb.consolidation_group,
        ctb.fiscal_year,
        ctb.fiscal_period,
        ctb.main_account,
        ctb.data_area_id
),

balance_eliminations as (
    select
        icr.rule_id as rule_id,
        icr.rule_name as rule_name,
        icr.rule_type as rule_type,
        db.consolidation_group as consolidation_group,
        db.fiscal_year as fiscal_year,
        db.fiscal_period as fiscal_period,
        icr.debit_account as debit_account,
        icr.credit_account as credit_account,
        {# F2: the two entities whose balances this cancels. They were computed
           here and thrown away, which left assert_equity_method_no_ic_elim
           unable to key on anything finer than the group — so one equity-method
           node in a group failed every elimination in it. Also the audit trail
           F10 wants: which pair a rule actually fired on. #}
        db.data_area_id as debit_entity,
        cr.data_area_id as credit_entity,
        least(abs(db.account_balance), abs(cr.account_balance)) as elimination_amount,
        -least(abs(db.account_balance), abs(cr.account_balance)) as debit_elimination,
        least(abs(db.account_balance), abs(cr.account_balance)) as credit_elimination
    from ic_rules as icr
    inner join ic_balances as db
        on db.main_account = icr.debit_account
    inner join ic_balances as cr
        on cr.main_account = icr.credit_account
        and cr.consolidation_group = db.consolidation_group
        and cr.fiscal_year = db.fiscal_year
        and cr.fiscal_period = db.fiscal_period
    where icr.rule_type = 'balance'
      and cr.data_area_id != db.data_area_id
      and (icr.debit_entity_pattern = '*' or db.data_area_id = icr.debit_entity_pattern)
      and (icr.credit_entity_pattern = '*' or cr.data_area_id = icr.credit_entity_pattern)
      {# PRD-14: Exclude equity-method entities from IC eliminations.
         F2: the method is dated and per-group, so the exclusion is too — it read
         the consolidation_groups seed, which had one method per entity for all
         time and none of the chain. An entity below an equity-held sub-group is
         equity-method at the top group while still line-consolidating into the
         sub-group, and only the (group, entity, period) key can say that. #}
      and (db.consolidation_group, db.data_area_id, db.fiscal_year, db.fiscal_period) not in (
          select consolidation_group, data_area_id, fiscal_year, fiscal_period
          from {{ ref('gold_entity_ownership') }}
          where consolidation_method = 'equity' or has_complete_chain = 0
      )
      and (cr.consolidation_group, cr.data_area_id, cr.fiscal_year, cr.fiscal_period) not in (
          select consolidation_group, data_area_id, fiscal_year, fiscal_period
          from {{ ref('gold_entity_ownership') }}
          where consolidation_method = 'equity' or has_complete_chain = 0
      )
),

{# PRD-15: Unrealized profit elimination
   elimination = ending_ic_inventory × margin%
   Dr Revenue offset, Cr Inventory #}
unrealized_profit_eliminations as (
    select
        icr.rule_id as rule_id,
        icr.rule_name as rule_name,
        icr.rule_type as rule_type,
        cg.consolidation_group as consolidation_group,
        icb.fiscal_year as fiscal_year,
        icb.fiscal_period as fiscal_period,
        icr.debit_account as debit_account,
        icr.asset_account as credit_account,
        icb.selling_entity as debit_entity,
        icb.buying_entity as credit_entity,
        icb.ending_inventory_from_ic * (icr.margin_pct / 100.0) as elimination_amount,
        -(icb.ending_inventory_from_ic * (icr.margin_pct / 100.0)) as debit_elimination,
        icb.ending_inventory_from_ic * (icr.margin_pct / 100.0) as credit_elimination
    from ic_rules as icr
    cross join {{ source('epm_staging', 'ic_balances') }} as icb
    {# F2: which group an entity rolls into is now one row per ANCESTOR group, so
       an unrealized-profit elimination is raised in every group that holds the
       buyer — including a parent group, which the single-level seed join never
       reached. distinct because the ownership model is period-grained and this
       join only needs the membership. #}
    inner join (
        select distinct consolidation_group, data_area_id
        from {{ ref('gold_entity_ownership') }}
        where has_complete_chain = 1 and consolidation_method != 'equity'
    ) as cg
        on icb.buying_entity = cg.data_area_id
    where icr.rule_type = 'unrealized_profit'
      and icb.ending_inventory_from_ic > 0
      and icr.margin_pct > 0
      and (icr.debit_entity_pattern = '*' or icb.selling_entity = icr.debit_entity_pattern)
      and (icr.credit_entity_pattern = '*' or icb.buying_entity = icr.credit_entity_pattern)
)

select * from balance_eliminations
union all
select * from unrealized_profit_eliminations
