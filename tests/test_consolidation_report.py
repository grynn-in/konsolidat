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


# --- konsol#117 pair 2 K3: eliminations are in full, the NCI block carries none -------

def test_the_report_reads_no_nci_amount_block():
    """Review fix: Consolidated is the FCTB layers only; the TB's nci_amount memo is not fetched."""
    assert not hasattr(report, "fetch_nci_data") and not hasattr(report, "fetch_nci_bs_cumulative")


def test_the_report_has_no_nci_elimination_layer():
    assert not hasattr(report, "_layer") and not hasattr(report, "_nci_view_legs")


# --- konsol#117 pair 2 review, finding 1: the minority is counted once ----------------

def _evaluate(ws, ref, depth=0):
    """Evaluate a cell of the form 'N' or '=A1+B1+...' (the only formulas the sheet writes here)."""
    import re
    v = ws[ref].value
    if isinstance(v, str) and v.startswith("="):
        return sum(_evaluate(ws, r) for r in re.findall(r"[A-Z]+\d+", v))
    return v or 0


def test_consolidated_is_the_sum_of_the_fctb_layers_with_a_70pct_entity():
    """Since K1 the entity layer is the subsidiary at 100% and K2 posts the minority's share as the
    'nci_attribution' layer. The Consolidated column is the sum of the layers of
    gold_fully_consolidated_tb and nothing else: a 30% 'NCI' block read from
    gold_consolidated_trial_balance.nci_amount on top shows a 70% subsidiary at 130%."""
    from openpyxl import Workbook
    from collections import defaultdict

    def tree():
        return defaultdict(lambda: defaultdict(lambda: defaultdict(float)))

    consol = tree()
    consol["entity"]["ZZ4000"]["Q1"] = -1000.0       # revenue, credit, the subsidiary at 100%
    consol["entity"]["ZZ3400"]["Q1"] = 0.0
    consol["nci_attribution"]["ZZ3400"]["Q1"] = -300.0  # the minority's share, in the NCI equity line
    sections = {"sections": [("Revenue", [("ZZ4000", "ZZ revenue")]),
                             ("Equity", [("ZZ3400", "ZZ NCI")])], "formulas": []}
    cfg = report.ConsolidationConfig(group="ZZGRP", year=2099)
    cfg.quarters = ["Q1"]
    ws = Workbook().active
    report.build_consolidated_sheet(ws, cfg, sections, consol, report.THEME_CONSOL, sign_flip=False)
    labels = {ws.cell(row=6, column=c).value: c for c in range(3, 12) if ws.cell(row=6, column=c).value}
    row = next(r for r in range(8, 20) if ws.cell(row=r, column=1).value == "ZZ4000")
    consolidated = _evaluate(ws, ws.cell(row=row, column=labels["Consolidated"]).coordinate)
    assert consolidated == -1000.0     # not -1300
    assert "NCI" not in labels
    assert "NCI attribution" in labels
    row = next(r for r in range(8, 20) if ws.cell(row=r, column=1).value == "ZZ3400")
    assert _evaluate(ws, ws.cell(row=row, column=labels["Consolidated"]).coordinate) == -300.0
