{{
    config(
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# IC elimination: find matching debit/credit account balances between entities
   and create offsetting entries #}
with ic_balances as (
    select
        ctb.consolidation_group as consolidation_group,
        ctb.fiscal_year as fiscal_year,
        ctb.fiscal_period as fiscal_period,
        ctb.main_account as main_account,
        ctb.data_area_id as data_area_id,
        sum(ctb.group_amount) as account_balance
    from {{ ref('gold_consolidated_trial_balance') }} as ctb
    inner join {{ ref('ic_elimination_rules') }} as icr
        on ctb.main_account = {{ cast_to_string('icr.debit_account') }}
        or ctb.main_account = {{ cast_to_string('icr.credit_account') }}
    group by
        ctb.consolidation_group,
        ctb.fiscal_year,
        ctb.fiscal_period,
        ctb.main_account,
        ctb.data_area_id
),

eliminations as (
    select
        icr.rule_id as rule_id,
        icr.rule_name as rule_name,
        db.consolidation_group as consolidation_group,
        db.fiscal_year as fiscal_year,
        db.fiscal_period as fiscal_period,
        {{ cast_to_string('icr.debit_account') }} as debit_account,
        {{ cast_to_string('icr.credit_account') }} as credit_account,
        least(abs(db.account_balance), abs(cr.account_balance)) as elimination_amount,
        -least(abs(db.account_balance), abs(cr.account_balance)) as debit_elimination,
        least(abs(db.account_balance), abs(cr.account_balance)) as credit_elimination
    from {{ ref('ic_elimination_rules') }} as icr
    inner join ic_balances as db
        on db.main_account = {{ cast_to_string('icr.debit_account') }}
    inner join ic_balances as cr
        on cr.main_account = {{ cast_to_string('icr.credit_account') }}
        and cr.consolidation_group = db.consolidation_group
        and cr.fiscal_year = db.fiscal_year
        and cr.fiscal_period = db.fiscal_period
    where cr.data_area_id != db.data_area_id
)

select * from eliminations
