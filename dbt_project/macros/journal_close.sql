{# journal_close macros (konsolidat#316). Design: chosen under the 5 Nov 2026
   standing rule (not a personal pick), recorded on #316 when the PR opens.
   No model uses these yet; the journal_close CTE in
   gold_fully_consolidated_tb and the year-end test read them.
#}

{# P&L codes outside the chart that the journal close must include.
   EQ_INCOME is a reserved pseudo-account written by
   gold_equity_method_associates (the share of an associate's profit). It is
   P&L, so it is closed to retained earnings. EQ_INVEST is the balance-sheet
   side and is not listed. A declared-account version is a separate decision.
   Usage: account_code in ({{ "'" ~ journal_pnl_pseudo_accounts() | join("','") ~ "'" }})
#}
{% macro journal_pnl_pseudo_accounts() %}
  {{ return(['EQ_INCOME']) }}
{% endmacro %}

{# Journal layers (adjustment_type) the journal close does NOT close.
   entity: closed by the #259 close in silver_tb_movements.
   ic_elimination: follows the entity close on the same accounts; it reverses
   its own P&L legs in the Closing period.
   A new journal layer is not listed here, so it is closed by default.
   Usage: adjustment_type not in ({{ "'" ~ journal_close_excluded_layers() | join("','") ~ "'" }})
#}
{% macro journal_close_excluded_layers() %}
  {{ return(['entity', 'ic_elimination']) }}
{% endmacro %}
