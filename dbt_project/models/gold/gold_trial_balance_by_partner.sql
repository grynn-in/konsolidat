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
    {{ dim_select(trailing=true) }}
    {{ measure_select() }},
    {# konsolidat#259: 1 on the rows of the year-end close silver_tb_movements
       synthesizes in a Closing period (silver_gl_entries marks them
       posting_layer 'Year-end close'). gold_consolidated_trial_balance
       translates those rows as a close: retained earnings takes the year's
       translated result, not its local result at a rate. A close an ERP posts
       itself carries no such mark and is translated as activity;
       assert_year_end_close_carries_no_cta names it. A key's close rows are
       never mixed with activity in one period (the close is synthesized only
       in a Closing period the entity did not claim), so max() is exact. #}
    toUInt8(max(posting_layer = 'Year-end close')) as is_year_end_close
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
    partner_data_area_id
    {{- dim_group_by(leading=true) }}
