{# journal_close macros (konsolidat#316). Design: chosen under the 5 Nov 2026
   standing rule (not a personal pick), recorded on #316 when the PR opens.
   The journal_close CTE in
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

{# The fiscal-year rule of the journal close (#357 re-review R1; chosen under the 5 Nov 2026 standing
   rule: the journal close follows the #259 entity close). One row per consolidation group with
   last_year = the latest fiscal year in the group's ENTITY layer (gold_consolidated_trial_balance: the
   members' own TB rows, which is what #259's years_to_close reads, per entity). A (group, fiscal year)
   is closed only when fiscal_year < last_year. A journal posting into a later year (a topside
   auto-reversing into next year's P1, a deal journal) does not close a year: until a member files the
   later year, #259 has not closed the entity P&L, so closing the journal P&L would split the year.
   Residual: a group whose later year is filed by only some members closes the year for all of them
   (the #259 close is per entity; the IC check in assert_journal_pnl_closed_at_year_end judges only
   entity-years #259 closed).
   Usage: inner join {{ journal_close_years() }} as y on y.consolidation_group = ... where fiscal_year < y.last_year
#}
{% macro journal_close_years() %}
    (
        select consolidation_group, max(fiscal_year) as last_year
        from {{ ref('gold_consolidated_trial_balance') }}
        group by consolidation_group
    )
{% endmacro %}
