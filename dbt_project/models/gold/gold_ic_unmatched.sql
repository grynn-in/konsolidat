{{
    config(
        engine='MergeTree()',
        order_by='tuple()',
        tags=['gold', 'domain:consolidation']
    )
}}

{# Intercompany balances with no partner (konsolidat#148, konsol#159).

   Decision 2 (13 Sep 2026): the partner is optional. A row on a flagged
   intercompany account without one is never eliminated and nothing guesses
   its counterparty; it stays in the consolidated figures and is listed here.
   Today that includes every D365 ledger line on an intercompany account: the
   ERP's partner is not mapped yet (see stg_d365_fo__gl_entries).

   One row per group, period, entity and account, in group currency (and in
   the entity's own currency). #}

with ic_accounts as (
    {{ ic_account_map() }}
)

select
    ctb.consolidation_group as consolidation_group,
    ctb.fiscal_year as fiscal_year,
    ctb.fiscal_period as fiscal_period,
    ctb.data_area_id as data_area_id,
    ctb.main_account as main_account,
    ica.counterpart as counterpart_account,
    sum(ctb.local_amount) as unmatched_local_amount,
    sum(ctb.group_amount) as unmatched_amount,
    'no partner' as reason
from {{ ref('gold_consolidated_trial_balance') }} as ctb
inner join ic_accounts as ica
    on ctb.main_account = ica.account
where ctb.partner_data_area_id = ''
group by
    ctb.consolidation_group,
    ctb.fiscal_year,
    ctb.fiscal_period,
    ctb.data_area_id,
    ctb.main_account,
    ica.counterpart
having abs(sum(ctb.group_amount)) >= 0.005
