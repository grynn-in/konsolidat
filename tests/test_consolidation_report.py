"""konsolidat#161: the report's entity columns follow the ownership window.

The consolidated column comes from gold_consolidated_trial_balance, which keeps
only the periods gold_entity_ownership says the group consolidates. The entity
columns must read the same periods, or an entity acquired mid-year shows
pre-acquisition amounts that nothing in the consolidated column matches.
"""
import importlib.util
import os

import pytest

pytest.importorskip("openpyxl")

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_spec = importlib.util.spec_from_file_location(
    "build_consolidation_report",
    os.path.join(PROJECT_ROOT, "scripts", "build_consolidation_report.py"),
)
report = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(report)


def _cfg():
    return report.ConsolidationConfig(
        group="ZZGRP",
        year=2099,
        entities=[{"data_area_id": "ZZOP", "entity_name": "ZZOP", "ownership_pct": 1.0,
                   "accounting_currency": "USD", "consolidation_method": "full"}],
    )


def _flat(sql):
    return " ".join(sql.split())


@pytest.mark.parametrize("fetch", [report.fetch_entity_pnl, report.fetch_entity_bs])
def test_entity_fetch_reads_only_the_ownership_window(fetch, monkeypatch):
    seen = []
    monkeypatch.setattr(report, "ch_query", lambda sql, cfg=None: seen.append(sql) or [])
    fetch(_cfg())
    assert len(seen) == 1
    sql = _flat(seen[0])
    assert ("AND (data_area_id, fiscal_year, fiscal_period) IN ( "
            "SELECT data_area_id, fiscal_year, fiscal_period "
            "FROM epm_gold.gold_entity_ownership") in sql
    for predicate in ("consolidation_group = 'ZZGRP'",
                      "fiscal_year = 2099",
                      "outside_ownership_window = 0",
                      "has_complete_chain = 1",
                      "consolidation_method NOT IN ('equity', 'none')"):
        assert predicate in sql, predicate


def test_window_matches_the_consolidated_model():
    """Drift guard: the report's window is the consolidated model's filter.

    If gold_consolidated_trial_balance changes which periods it consolidates,
    ownership_window_filter must change with it.
    """
    path = os.path.join(PROJECT_ROOT, "dbt_project", "models", "gold",
                        "gold_consolidated_trial_balance.sql")
    with open(path) as f:
        model = _flat(f.read())
    assert "where eo.consolidation_method not in ('equity', 'none') and eo.has_complete_chain = 1" in model
    window = _flat(report.ownership_window_filter(_cfg()))
    assert "has_complete_chain = 1" in window
    assert "consolidation_method NOT IN ('equity', 'none')" in window


def test_windowed_rows_still_aggregate_by_quarter(monkeypatch):
    """The fetches still bucket what ClickHouse returns; only the SQL changed."""
    monkeypatch.setattr(report, "ch_query", lambda sql, cfg=None: [
        {"data_area_id": "ZZOP", "main_account": "4010", "quarter": "Q3", "amount": "-24000"},
        {"data_area_id": "ZZOP", "main_account": "4010", "quarter": "Q4", "amount": "-33000"},
    ])
    pnl = report.fetch_entity_pnl(_cfg())
    assert dict(pnl["ZZOP"]["4010"]) == {"Q3": -24000.0, "Q4": -33000.0}

    monkeypatch.setattr(report, "ch_query", lambda sql, cfg=None: [
        {"data_area_id": "ZZOP", "main_account": "1010", "fiscal_period": 9, "amount": "45000"},
    ])
    bs = report.fetch_entity_bs(_cfg())
    assert dict(bs["ZZOP"]["1010"]) == {"Q3": 45000.0}


# --- konsolidat#148 / #175 re-review H1: the NCI view's eliminations ---------

@pytest.mark.parametrize("fetch", [report.fetch_nci_data, report.fetch_nci_bs_cumulative])
def test_the_nci_block_eliminates_the_minoritys_share_of_intragroup_balances(fetch, monkeypatch):
    """The Consolidated column is the group view plus the NCI block. The NCI
    block adds the NCI view's eliminations to nci_amount, so an intragroup
    balance with an 80%-owned side nets to zero at 100%."""
    seen = []
    monkeypatch.setattr(report, "ch_query", lambda sql, cfg=None: seen.append(sql) or [])
    fetch(_cfg())
    sql = _flat(seen[0])
    assert "FROM epm_gold.gold_consolidated_trial_balance" in sql
    assert "FROM epm_gold.gold_ic_eliminations" in sql and "elimination_view = 'nci'" in sql
    # both legs of each entry, and only chart accounts (the NCI line is not one)
    assert "debit_elimination AS leg_amount" in sql and "credit_elimination" in sql
    assert "INNER JOIN epm_silver.silver_main_accounts" in sql
    assert "sum(amount) AS nci_total" in sql


def test_a_payable_at_an_80pct_entity_nets_to_zero_at_100pct(monkeypatch):
    """B (80%) owes A (100%) 1000. Group view: payable -800 + 800 matched = 0.
    NCI block: nci_amount -200 plus the NCI view's +200 = 0. The rows come
    back already summed by the query, as ClickHouse returns them."""
    monkeypatch.setattr(report, "ch_query", lambda sql, cfg=None: [
        {"main_account": "2010", "is_pnl": 0, "is_balance_sheet": 1, "quarter": "Q1", "nci_total": -200.0 + 200.0},
    ])
    pnl, bs = report.fetch_nci_data(_cfg())
    assert bs["2010"]["Q1"] == 0.0 and not pnl


def test_nci_entries_are_reported_with_the_ic_eliminations():
    assert report._layer("ic_elimination_nci") == "ic_elimination"
    assert report._layer("ic_elimination") == "ic_elimination"
    assert report._layer("cta") == "cta"
