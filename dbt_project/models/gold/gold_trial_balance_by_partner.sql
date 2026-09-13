{{
    config(
        engine=cluster_engine('MergeTree()'),
        order_by='tuple()',
        cluster=cluster_name()
    )
}}

{# gold_trial_balance with one row per intercompany partner (konsol#159).

   gold_trial_balance keeps its account grain. Its readers join and window on
   (entity, period, account, dimensions): the prior-year comparison, the YTD
   running sum and the P&L views. A row per partner there fanned them out
   (#175 review: 300 instead of 150 year on year, 250 instead of 150 YTD).

   Only consolidation needs the partner, so it reads this model:
   gold_consolidated_trial_balance, and through it gold_ic_reconciliation and
   gold_ic_unmatched. partner_data_area_id is '' where a row has none.
   Summing this model over partner_data_area_id gives gold_trial_balance. #}

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
    {{ dim_select() }},
    {{ measure_select() }}
from {{ ref('silver_gl_entries') }}
group by
    data_area_id,
    fiscal_year,
    fiscal_period,
    main_account,
    account_name,
    account_type_name,
    is_balance_sheet,
    is_pnl,
    partner_data_area_id,
    {{ dim_group_by() }}
