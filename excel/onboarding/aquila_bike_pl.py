#!/usr/bin/env python3
"""The Aquila Bike example as a 12-line P&L, three ways: before and after consolidation (FY2024), the
month before and the month of the acquisition of ABCZ (P5, P6), the month before and the month of the
disposal of ABDK (P11, P12).

    uv run aquila_bike_pl.py                 -> Markdown tables (EUR thousand) for the example's README
    uv run aquila_bike_pl.py --unit 1        -> the same in EUR

Every figure is read from examples/aquila-bike/model/expected.json (the Python replica of the warehouse,
which the live build matches to the cent; see README "Verification"): the `fctb` layers for the
consolidated columns and the bridge, the `translation` rows for the entities at 100%. Nothing is typed in.
Presentation is credit-positive (revenue and profit positive, costs negative), the tool view (subsidiaries at
the group's share, no NCI line). Every P&L account of the chart must fall into a line, or this script stops.
"""
from __future__ import annotations

import argparse
import json
import os
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
EXPECTED = os.path.join(HERE, "examples", "aquila-bike", "model", "expected.json")

FY = 2024
PERIODS_FY = ["%d-%d" % (FY, p) for p in range(1, 13)]
ACQUIRED, ACQ_PERIOD, PRE_ACQ = "ABCZ", "2024-6", "2024-5"
DISPOSED, DSP_PERIOD, PRE_DSP = "ABDK", "2024-12", "2024-11"

#: line -> (label, predicate on the account). Order is the order of the statement; subtotals are computed.
LINES = [
    ("revenue", "Revenue, net of dealer discounts (4110-4220, 4910)", lambda a: a[:2] in ("41", "42", "49")),
    ("ic_revenue", "Intercompany revenue: goods and management fees (4310, 4340)", lambda a: a[:2] == "43"),
    ("cos", "Cost of sales, incl. intercompany purchases and fees (51xx-55xx)", lambda a: a[0] == "5"),
    ("gross_profit", "**Gross profit**", None),
    ("opex", "Operating expenses net of other income: staff, selling, admin, R&D (61xx-65xx, 67x0 except deals)",
     lambda a: a[:2] in ("61", "62", "63", "64", "65") or a in ("6710", "6720", "6750", "6790")),
    ("da", "Depreciation, amortisation, impairment (66xx)", lambda a: a[:2] == "66"),
    ("deals", "Deal items: acquisition costs (6770), gain on disposal (6730), bargain purchase (6760)",
     lambda a: a in ("6730", "6760", "6770")),
    ("operating_profit", "**Operating profit**", None),
    ("fin", "Financial items, net, incl. intercompany interest (71xx, 72xx)", lambda a: a[0] == "7"),
    ("associate", "Share of result of the associate ABPT, 30% (EQ_INCOME)", lambda a: a == "EQ_INCOME"),
    ("tax", "Income taxes (8xxx)", lambda a: a[0] == "8"),
    ("net_result", "**Net result for the period (group share)**", None),
]
SUBTOTALS = {
    "gross_profit": ("revenue", "ic_revenue", "cos"),
    "operating_profit": ("gross_profit", "opex", "da", "deals"),
    "net_result": ("operating_profit", "fin", "associate", "tax"),
}


def is_pnl(account: str) -> bool:
    return account[0] in "45678" or account == "EQ_INCOME"


def line_of(account: str) -> str:
    hits = [key for key, _, pred in LINES if pred and pred(account)]
    if len(hits) != 1:
        raise SystemExit("account %s falls into %d lines: %s" % (account, len(hits), hits))
    return hits[0]


def statement(by_account: dict[str, float]) -> dict[str, float]:
    """Account sums (Dr +) -> line values, credit-positive, with subtotals."""
    out = defaultdict(float)
    for account, amount in by_account.items():
        if is_pnl(account):
            out[line_of(account)] -= amount
    for key, parts in SUBTOTALS.items():
        out[key] = sum(out[p] for p in parts)
    return out


def sum_rows(rows, periods, types=None, entities=None, field="amount") -> dict[str, float]:
    acc = defaultdict(float)
    for r in rows:
        if r["period"] in periods and (types is None or r["type"] in types) and (entities is None or r["entity"] in entities):
            acc[r["account"]] += r[field]
    return acc


def columns(expected: dict) -> dict[str, dict[str, dict[str, float]]]:
    """Three tables: {table: {column: {line: value}}}."""
    f, t = expected["fctb"], expected["translation"]
    # 1. FY2024, before and after consolidation. The bridge columns are the warehouse's own layers; the first
    #    column is the ten entities at 100% (translation.translated), the second takes the minority's 30% of
    #    ABSE out (translation.nci), which is how the entity layer of the tool reaches the group's share.
    consolidation = {
        "Ten entities summed, 100%": statement(sum_rows(t, PERIODS_FY, field="translated")),
        "Minority's 30% of ABSE": {k: -v for k, v in statement(sum_rows(t, PERIODS_FY, field="nci")).items()},
        "Intercompany eliminations": statement(sum_rows(f, PERIODS_FY, {"ic_elimination", "ic_elimination_nci"})),
        "Deal journals": statement(sum_rows(f, PERIODS_FY, {"acquisition", "disposal"})),
        "Equity method": statement(sum_rows(f, PERIODS_FY, {"equity_method"})),
        "Consolidated FY2024": statement(sum_rows(f, PERIODS_FY)),
    }
    for layer in ("cta", "topside"):
        assert not any(is_pnl(a) for a in sum_rows(f, PERIODS_FY, {layer})), layer + " layer hit a P&L account"
    # 2. and 3. one consolidated month before, the deal month, and what the deal month owes to the deal
    acquisition = {
        "P5 (May) consolidated": statement(sum_rows(f, {PRE_ACQ})),
        "P6 (June) consolidated": statement(sum_rows(f, {ACQ_PERIOD})),
        "of which ABCZ's own June (entity layer)": statement(sum_rows(f, {ACQ_PERIOD}, {"entity"}, {ACQUIRED})),
        "of which the acquisition journal": statement(sum_rows(f, {ACQ_PERIOD}, {"acquisition"})),
    }
    disposal = {
        "P11 (Nov) consolidated": statement(sum_rows(f, {PRE_DSP})),
        "P12 (Dec) consolidated": statement(sum_rows(f, {DSP_PERIOD})),
        "of which ABDK's own December (entity layer)": statement(sum_rows(f, {DSP_PERIOD}, {"entity"}, {DISPOSED})),
        "of which the disposal journal": statement(sum_rows(f, {DSP_PERIOD}, {"disposal"})),
    }
    return {"consolidation": consolidation, "acquisition": acquisition, "disposal": disposal}


def check(tables: dict) -> None:
    c = tables["consolidation"]
    bridge = [k for k in c if k != "Consolidated FY2024"]
    for key, _, _ in LINES:
        total = sum(c[col][key] for col in bridge)
        assert abs(total - c["Consolidated FY2024"][key]) < 0.01, (key, total, c["Consolidated FY2024"][key])


def notes(tables: dict, expected: dict) -> dict[str, float]:
    """The reconciliation a reader of IFRS 10 will ask for: the tool's result vs the owners' result at 100%.

    The ic_elimination_nci rows are the minority's 30% of the group's sales, fees and interest to ABSE; the tool
    removes them from the P&L and books them to NCI equity (3700, decision 12), so its result is lower than the
    owners' result of an IFRS statement by exactly that amount (Statements sheet of the walkthrough, reconciliation line)."""
    c = tables["consolidation"]
    # the legs are debits to revenue and interest income (Dr +): what the tool's P&L lost to equity, so added back
    nci_legs = sum(v for a, v in sum_rows(expected["fctb"], PERIODS_FY, {"ic_elimination_nci"}).items() if is_pnl(a))
    tool = c["Consolidated FY2024"]["net_result"]
    minority = -c["Minority's 30% of ABSE"]["net_result"]
    return {"tool_result": tool, "nci_legs_to_equity": nci_legs, "owners_result_ifrs": tool + nci_legs,
            "minority_share_of_result": minority, "total_result_100pct": tool + nci_legs + minority}


def fmt(v: float, unit: int) -> str:
    x = round(v / unit)
    if x == 0:
        return "–"
    return ("({:,})".format(-x)) if x < 0 else "{:,}".format(x)


def markdown(tables: dict, unit: int, notes_: dict | None = None) -> str:
    out = []
    unit_name = {1: "EUR", 1000: "EUR thousand"}.get(unit, "EUR / %d" % unit)
    for title, table in (("Before and after consolidation, FY2024", tables["consolidation"]),
                         ("Before and after the acquisition of ABCZ (1 June 2024)", tables["acquisition"]),
                         ("Before and after the disposal of ABDK (31 December 2024)", tables["disposal"])):
        cols = list(table)
        out.append("**%s** (%s; costs in brackets)\n" % (title, unit_name))
        out.append("| Line | " + " | ".join(cols) + " |")
        out.append("|---|" + "---:|" * len(cols))
        for key, label, _ in LINES:
            cells = [fmt(table[c][key], unit) for c in cols]
            if key in SUBTOTALS:
                cells = ["**%s**" % x for x in cells]
            out.append("| %s | %s |" % (label, " | ".join(cells)))
        out.append("")
        if notes_ and table is tables["consolidation"]:
            out.append("IFRS 10 view of the same year: total result at 100%% %s, of which non-controlling interests %s and "
                       "owners of the parent %s. The owners' result is %s above the tool's: the minority's 30%% of the "
                       "group's sales, fees and interest to ABSE, which the tool takes out of the P&L and books to NCI "
                       "equity (3700, decision 12)." % tuple(fmt(notes_[k], unit) for k in
                       ("total_result_100pct", "minority_share_of_result", "owners_result_ifrs", "nci_legs_to_equity")))
            out.append("")
    return "\n".join(out)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--unit", type=int, default=1000, help="divide by this (1000 = EUR thousand, the default)")
    ap.add_argument("--json", action="store_true", help="print the tables as JSON at full precision")
    args = ap.parse_args()
    with open(EXPECTED) as fh:
        expected = json.load(fh)
    chart_pnl = {a for a in {r["account"] for r in expected["fctb"]} if is_pnl(a)}
    for a in sorted(chart_pnl):
        line_of(a)   # every P&L account the warehouse produced falls into exactly one line
    tables = columns(expected)
    check(tables)
    n = notes(tables, expected)
    if args.json:
        print(json.dumps({"tables": tables, "notes": n}, indent=1))
    else:
        print(markdown(tables, args.unit, n))


if __name__ == "__main__":
    main()
