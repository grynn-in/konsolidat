#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = ["openpyxl>=3.1"]
# ///
"""Build Aquila_Bike_Walkthrough.xlsx: the Aquila Bike consolidation done offline in Excel, with live
formulas, following the warehouse's rules step by step (movements -> ownership window -> translation ->
CTA -> intercompany -> deal journals -> equity method -> topside -> consolidated TB -> statements), so a
client can audit every number and compare it with konsol live (=K.EPM) and with the Python replica.

    uv run build_aquila_bike_walkthrough.py

Reads examples/aquila-bike/model/inputs.json and expected.json (build_aquila_bike.py, aquila_bike_offline.py).
The ROW STRUCTURE of every sheet (which keys, periods, pairs exist) is laid out by this script; every
AMOUNT, RATE and TOTAL is an Excel formula.
"""
from __future__ import annotations

import datetime as dt
import json
import os
import sys

from openpyxl import Workbook
from openpyxl.comments import Comment
from openpyxl.styles import Alignment, Font, PatternFill
from openpyxl.utils import get_column_letter as L

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from aquila_bike_offline import Offline, load_inputs  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
EX = os.path.join(HERE, "examples", "aquila-bike")
OUT = os.path.join(EX, "Aquila_Bike_Walkthrough.xlsx")

FONT = "Arial"
F_BODY = Font(name=FONT, size=10)
F_BOLD = Font(name=FONT, size=10, bold=True)
F_HEAD = Font(name=FONT, size=10, bold=True, color="FFFFFF")
F_INPUT = Font(name=FONT, size=10, color="0000FF")
F_LINK = Font(name=FONT, size=10, color="008000")
F_TITLE = Font(name=FONT, size=14, bold=True, color="1F3864")
F_H2 = Font(name=FONT, size=11, bold=True, color="1F3864")
FILL_HEAD = PatternFill("solid", fgColor="1F3864")
FILL_KEY = PatternFill("solid", fgColor="FFF2CC")
FILL_CHECK = PatternFill("solid", fgColor="E2EFDA")
NUM = '#,##0.00;(#,##0.00);"-"'
RATE = "0.000000"
WRAP = Alignment(wrap_text=True, vertical="top")

NCI_ENTITY = "ABSE"


def pl(p):
    return "%d-%d" % tuple(p)


def head(ws, row, headers, widths=None, comments=None):
    for i, h in enumerate(headers, 1):
        c = ws.cell(row=row, column=i, value=h)
        c.font = F_HEAD
        c.fill = FILL_HEAD
        c.alignment = Alignment(wrap_text=True, vertical="center")
        if comments and h in comments:
            c.comment = Comment(comments[h], "aquila-bike walkthrough")
        if widths:
            ws.column_dimensions[L(i)].width = widths[i - 1] if i - 1 < len(widths) else 14
    ws.row_dimensions[row].height = 30
    ws.freeze_panes = ws.cell(row=row + 1, column=1)


def put(ws, r, c, v, font=F_BODY, fmt=None):
    cell = ws.cell(row=r, column=c, value=v)
    cell.font = font
    if fmt:
        cell.number_format = fmt
    return cell


def build():
    d = load_inputs()
    o = Offline(d).run()
    with open(os.path.join(EX, "model", "expected.json")) as f:
        exp = json.load(f)
    periods = [tuple(p) for p in d["periods"]]
    spine = sorted({p for e in o.mov for p in o.mov[e]})          # includes (2023, 13)
    ord_of = {p: i + 1 for i, p in enumerate(spine)}
    gcur = d["group_currency"]
    currencies = [c for c in sorted({e["currency"] for e in d["entities"].values()}) if c != gcur]
    chart_codes = [a for a in sorted(d["chart"])]
    wb = Workbook()

    # ------------------------------------------------------------------ README
    ws = wb.active
    ws.title = "README"
    ws.column_dimensions["A"].width = 150
    lines = [
        ("Aquila Bike Group - offline consolidation walkthrough (FY2023 year end, FY2024 P1-P12)", F_TITLE),
        ("", F_BODY),
        ("What this workbook is", F_H2),
        ("The whole consolidation of the fictional Aquila Bike Group done in Excel with live formulas, following the same rules the konsolidat "
         "warehouse applies, step by step. It is the audit trail for the demo: every figure the tool shows can be traced here to the trial "
         "balances in tb/, the governed rates, the ownership periods, the two deals and the opening journal.", F_BODY),
        ("Only the row structure (which accounts, periods and intercompany pairs exist) was laid out by the generator; every amount, rate "
         "and total is a formula. Inputs are blue; formulas black; the green columns are checks that must read zero.", F_BODY),
        ("", F_BODY),
        ("The story, period by period (see sheet Walkthrough)", F_H2),
        ("1 Jan 2024: ten consolidated entities and one 30% associate; the FY2023 year-end trial balances are the opening position. The holding's "
         "investments are eliminated against the subsidiaries' share capital by the opening journal (sheet Topside).", F_BODY),
        ("FY2024 P1-P5: monthly closes. Balance sheets at each month's closing rate, P&L at each month's average rate, share capital at "
         "historical rates, the difference in CTA. Intercompany pairs eliminated on the declared account pairs with the partner on both sides.", F_BODY),
        ("FY2024 P6: ABCZ (Czech, CZK) acquired 100% on 1 June 2024 for EUR 11.0m: goodwill, fair value step-up on plant, costs expensed "
         "(sheet Acquisition). ABCZ contributes June onwards only; its 31 May balance sheet enters through the acquisition journal.", F_BODY),
        ("FY2024 P7-P11: ABCZ fully in; management fees to ABCZ start.", F_BODY),
        ("FY2024 P12: ABDK (Danish, DKK) sold 100% on 31 December 2024 for EUR 7.0m: net assets derecognised at the December closing rate, "
         "CTA recycled, gain on disposal (sheet Disposal). ABDK's full-year result stays in the group result.", F_BODY),
        ("Year end: consolidated P&L FY2024 and balance sheet at 31 Dec 2024 (sheet Statements). Any earlier month can be re-read: the "
         "warehouse keeps every period's movements, and =K.EPM(\"AQBIKE\", 2024, 7, account, \"consolidated_amount\", \"consolidated\") "
         "reads it live (sheet LiveCheck).", F_BODY),
        ("", F_BODY),
        ("What the tool does that an IFRS reader should know (said plainly)", F_H2),
        ("1. Partly owned subsidiaries are carried at the group's share (ABSE at 70%); the minority's 30% is computed per row (column nci) "
         "but there is no NCI line in the tool's statements (konsolidat#204). Sheet Statements shows both: the tool's view and the IFRS 10 "
         "view (100% plus an NCI line), with the reconciliation between them.", F_BODY),
        ("2. A deal must be dated on the first day of a period (konsolidat#278) and its acquired balance sheet is the last period-end before "
         "the acquisition period (konsol#406). The example does both.", F_BODY),
        ("3. The acquired entity's opening balance sheet is frozen at the acquisition-period closing rate (never retranslated); the goodwill "
         "likewise. Its own movements from the acquisition period on are retranslated normally.", F_BODY),
        ("4. The parent's own books record deal cash through the group's Deal Settlement Account (1235) and keep the investment at cost; "
         "the acquisition journal credits the investment, the disposal journal debits the proceeds. No template eliminates a parent's own "
         "gain on disposal, so the example's parent books none.", F_BODY),
        ("5. The equity-method entry (associate ABPT) is shown as it must be: share of result at the average rate, debit investment / credit "
         "income. The warehouse model posted both legs with one sign and untranslated when this was written (konsolidat issue filed 7 Nov 2026; fixed on branch fix-equity-method-journal).", F_BODY),
        ("", F_BODY),
        ("Sheets", F_H2),
    ]
    guide = [
        ("Walkthrough", "the story with the key figures linked to the sheets below"),
        ("Entities, Chart, Periods, Rates", "master data: entities and ownership, the group chart with each account's translation rule, the calendar, governed Closing/Average rates and the historical equity rates"),
        ("TB", "every trial-balance line as uploaded (period-end balances, local currency, debit +, credit -), one row per entity, period, account and partner"),
        ("Rows", "the warehouse's consolidated trial-balance rows: movement from the balances (first file = the balance, year-end close synthesised in 2023-13), ownership window, rate, retranslation of balance-sheet balances to each closing rate, the close translation, group and NCI share"),
        ("CTA", "the translation difference per entity and period: minus the sum of the entity's group amounts"),
        ("IC", "intercompany pairs matched on translated amounts (balances cumulative, P&L by period), the shares each side is carried at, matched / residual, and the elimination legs"),
        ("Acquisition, Disposal", "the two deal journals line by line"),
        ("EquityMethod, Topside", "the associate's share of result; the opening elimination journal"),
        ("ConsolTB", "the fully consolidated trial balance per period and layer, with the Python replica as a cross-check column (must be 0) and the IFRS 100% view"),
        ("Statements", "P&L per period and FY, balance sheet per period end: tool view, IFRS view, reconciliation"),
        ("LiveCheck", "the =K.EPM formulas that read the same figures from konsol live (text here; paste into a signed-in Excel)"),
    ]
    r = 1
    for text, font in lines:
        c = put(ws, r, 1, text, font)
        c.alignment = WRAP
        if font is F_BODY and len(text) > 140:
            ws.row_dimensions[r].height = 15 * (len(text) // 140 + 1)
        r += 1
    for name, what in guide:
        put(ws, r, 1, "%s: %s" % (name, what)).alignment = WRAP
        ws.row_dimensions[r].height = 15 * (len(what) // 140 + 1)
        r += 1

    # ------------------------------------------------------------------ Entities
    ws = wb.create_sheet("Entities")
    head(ws, 1, ["code", "name", "currency", "ownership %", "method", "owned since", "owned until", "consolidated?", "in group view: share"],
         [8, 34, 9, 11, 10, 12, 12, 13, 14],
         {"owned until": "Blank in konsol means still owned; here 9999-12-31. ABDK: the disposal date.",
          "consolidated?": "full or proportional: line by line. equity: one-line share of result. none: excluded."})
    ent_codes = sorted(d["entities"], key=lambda c: (c != "ABH", c))
    ent_row = {}
    for i, code in enumerate(ent_codes, 2):
        e = d["entities"][code]
        ent_row[code] = i
        put(ws, i, 1, code, F_INPUT); put(ws, i, 2, e["name"]); put(ws, i, 3, e["currency"], F_INPUT)
        put(ws, i, 4, e["own"] / 100.0, F_INPUT, "0%"); put(ws, i, 5, e["method"], F_INPUT)
        put(ws, i, 6, dt.date.fromisoformat(e["since"]), F_INPUT, "yyyy-mm-dd")
        until = dt.date.fromisoformat(d["disposal"]["date"]) if code == d["disposal"]["entity"] else dt.date(9999, 12, 31)
        put(ws, i, 7, until, F_INPUT, "yyyy-mm-dd")
        put(ws, i, 8, '=IF(OR(E%d="equity",E%d="none"),"no","yes")' % (i, i))
        put(ws, i, 9, '=IF(H%d="yes",D%d,0)' % (i, i), fmt="0%")
    n_ent = len(ent_codes) + 1
    ENT = "Entities!$A$2:$A$%d" % n_ent

    def ent_col(col):
        return "Entities!$%s$2:$%s$%d" % (col, col, n_ent)

    # ------------------------------------------------------------------ Chart
    ws = wb.create_sheet("Chart")
    head(ws, 1, ["account", "name", "type", "statement", "fx_method", "is_equity", "is_pnl", "is_bs", "is_retained_earnings", "retranslated?"],
         [9, 44, 10, 14, 11, 9, 8, 8, 12, 12],
         {"fx_method": "The rate konsolidat translates the account at (IAS 21): average for P&L, closing for balance sheet, historical for share capital and premium.",
          "retranslated?": "A balance-sheet account that is not equity and is declared closing: its cumulative balance is restated to each period's closing rate."})
    chart_row = {}
    for i, a in enumerate(chart_codes, 2):
        acc = d["chart"][a]
        chart_row[a] = i
        flags = (acc["flags"] or "").split()
        put(ws, i, 1, a, F_INPUT); put(ws, i, 2, acc["name"]); put(ws, i, 3, acc["type"], F_INPUT)
        put(ws, i, 4, '=IF(OR(C%d="Revenue",C%d="Expense"),"PL","BS")' % (i, i))
        put(ws, i, 5, "historical" if "hist" in flags else ("average" if acc["type"] in ("Revenue", "Expense") else "closing"), F_INPUT)
        put(ws, i, 6, '=IF(C%d="Equity",1,0)' % i); put(ws, i, 7, '=IF(D%d="PL",1,0)' % i); put(ws, i, 8, '=IF(D%d="BS",1,0)' % i)
        put(ws, i, 9, 1 if "RE" in flags else 0, F_INPUT)
        put(ws, i, 10, '=IF(AND(H%d=1,F%d=0,E%d="closing"),1,0)' % (i, i, i))
    # pseudo accounts the warehouse posts to
    for a, name in (("CTA", "Currency translation adjustment (warehouse line)"), ("EQ_INCOME", "Equity method - share of result"), ("EQ_INVEST", "Equity method - investment")):
        i = len(chart_codes) + 2 + ["CTA", "EQ_INCOME", "EQ_INVEST"].index(a)
        chart_row[a] = i
        put(ws, i, 1, a, F_INPUT); put(ws, i, 2, name)
        put(ws, i, 3, "Revenue" if a == "EQ_INCOME" else "Equity" if a == "CTA" else "Asset", F_INPUT)
        put(ws, i, 4, '=IF(OR(C%d="Revenue",C%d="Expense"),"PL","BS")' % (i, i)); put(ws, i, 5, "n/a", F_INPUT)
        put(ws, i, 6, '=IF(C%d="Equity",1,0)' % i); put(ws, i, 7, '=IF(D%d="PL",1,0)' % i); put(ws, i, 8, '=IF(D%d="BS",1,0)' % i)
        put(ws, i, 9, 0, F_INPUT); put(ws, i, 10, 0)
    n_chart = len(chart_codes) + 4
    CH = "Chart!$A$2:$A$%d" % n_chart

    def ch_col(col):
        return "Chart!$%s$2:$%s$%d" % (col, col, n_chart)

    def ch_lookup(col, acct_ref):
        return "INDEX(%s,MATCH(%s,%s,0))" % (ch_col(col), acct_ref, CH)

    # ------------------------------------------------------------------ Periods
    ws = wb.create_sheet("Periods")
    head(ws, 1, ["period", "year", "number", "ordinal", "first day", "type", "rate period"], [10, 7, 8, 8, 12, 9, 11],
         {"first day": "The date the ownership window is tested on (konsolidat#278): the first day of the period's month; 13 maps to 1 December.",
          "rate period": "A Closing period has no rates of its own and uses the last Regular period's (2023-13 -> 2023-12)."})
    per_row = {}
    for i, p in enumerate(spine, 2):
        per_row[p] = i
        put(ws, i, 1, pl(p), F_INPUT); put(ws, i, 2, p[0], F_INPUT); put(ws, i, 3, p[1], F_INPUT); put(ws, i, 4, ord_of[p])
        put(ws, i, 5, '=DATE(B%d,MIN(MAX(C%d,1),12),1)' % (i, i), fmt="yyyy-mm-dd")
        put(ws, i, 6, "Closing" if p[1] == 13 else "Regular", F_INPUT)
        put(ws, i, 7, '=IF(F%d="Closing",B%d&"-12",A%d)' % (i, i, i))
    n_per = len(spine) + 1
    PER = "Periods!$A$2:$A$%d" % n_per

    def per_col(col):
        return "Periods!$%s$2:$%s$%d" % (col, col, n_per)

    # ------------------------------------------------------------------ Rates
    ws = wb.create_sheet("Rates")
    rate_cols = ["period"] + ["Closing %s" % c for c in currencies] + ["Average %s" % c for c in currencies]
    head(ws, 1, rate_cols, [10] + [13] * (len(rate_cols) - 1),
         {"period": "Governed Group Exchange Rates (FX_Rates sheet of the master workbook): units of EUR per 1 unit of the currency, as the warehouse stores them (quote / quoted_per)."})
    for i, p in enumerate(periods, 2):
        put(ws, i, 1, pl(p), F_INPUT)
        for j, c in enumerate(currencies):
            put(ws, i, 2 + j, d["rates"][pl(p)]["Closing"][c], F_INPUT, RATE)
            put(ws, i, 2 + len(currencies) + j, d["rates"][pl(p)]["Average"][c], F_INPUT, RATE)
    n_rates = len(periods) + 1
    RP = "Rates!$A$2:$A$%d" % n_rates
    RH = "Rates!$B$1:$%s$1" % L(len(rate_cols))
    RB = "Rates!$B$2:$%s$%d" % (L(len(rate_cols)), n_rates)
    hr0 = n_rates + 3
    put(ws, hr0 - 1, 1, "Historical equity rates (IAS 21): the frozen rate of each foreign entity's share capital and premium", F_H2)
    head(ws, hr0, ["entity", "rate date", "historical rate", "accounts"], [10, 12, 14, 14])
    ws.freeze_panes = "A2"
    hist_entities = sorted(d["hist_rates"])
    for i, e in enumerate(hist_entities, hr0 + 1):
        put(ws, i, 1, e, F_INPUT); put(ws, i, 2, dt.date.fromisoformat(d["entities"][e]["since"]), F_INPUT, "yyyy-mm-dd")
        put(ws, i, 3, d["hist_rates"][e], F_INPUT, RATE); put(ws, i, 4, "3100, 3200")
    HE = "Rates!$A$%d:$A$%d" % (hr0 + 1, hr0 + len(hist_entities))
    HD = "Rates!$B$%d:$B$%d" % (hr0 + 1, hr0 + len(hist_entities))
    HRt = "Rates!$C$%d:$C$%d" % (hr0 + 1, hr0 + len(hist_entities))

    def rate_formula(kind, cur_ref, rateper_ref):
        """kind: 'Closing' or 'Average'; 1 when the currency is the group's."""
        return 'IF(%s="%s",1,INDEX(%s,MATCH(%s,%s,0),MATCH("%s "&%s,%s,0)))' % (cur_ref, gcur, RB, rateper_ref, RP, kind, cur_ref, RH)

    # ------------------------------------------------------------------ TB (inputs)
    ws = wb.create_sheet("TB")
    head(ws, 1, ["entity", "period", "account", "partner", "amount (local, Dr +)", "key", "is_pnl"], [8, 9, 9, 9, 18, 30, 7],
         {"amount (local, Dr +)": "Period-end balance as uploaded in tb/TB_<period>.xlsx: debit - credit, in the entity's currency.",
          "key": "entity|account|partner|period: what the Rows sheet looks balances up by."})
    tb_rows = sorted(d["tb_cents"], key=lambda t: (t[0], t[3], t[4], t[1], t[2]))
    for i, (e, y, p, a, partner, cents) in enumerate(tb_rows, 2):
        put(ws, i, 1, e, F_INPUT); put(ws, i, 2, "%d-%d" % (y, p), F_INPUT); put(ws, i, 3, a, F_INPUT); put(ws, i, 4, partner, F_INPUT)
        put(ws, i, 5, cents / 100.0, F_INPUT, NUM)
        put(ws, i, 6, '=A%d&"|"&C%d&"|"&D%d&"|"&B%d' % (i, i, i, i))
        put(ws, i, 7, "=" + ch_lookup("G", "C%d" % i))
    n_tb = len(tb_rows) + 1
    TBK, TBA, TBE, TBP, TBPL = ("TB!$F$2:$F$%d" % n_tb, "TB!$E$2:$E$%d" % n_tb, "TB!$A$2:$A$%d" % n_tb, "TB!$B$2:$B$%d" % n_tb, "TB!$G$2:$G$%d" % n_tb)

    # ------------------------------------------------------------------ Rows (movements + translation)
    ws = wb.create_sheet("Rows")
    cols = ["entity", "period", "ordinal", "account", "partner", "kind", "previous period", "balance now", "balance before", "movement (local)",
            "in window", "local in scope", "currency", "fx_method", "rate period", "rate", "closing rate", "previous closing", "cumulative before",
            "retranslation", "close adj P&L", "close adj RE", "translated", "share", "group amount", "nci amount", "key", "is_bs", "is_equity", "is_pnl", "retranslated key", "year"]
    head(ws, 1, cols, [7, 8, 6, 7, 7, 10, 9, 14, 14, 14, 6, 14, 7, 9, 9, 10, 10, 10, 14, 13, 13, 13, 14, 6, 14, 14, 26, 5, 6, 6, 6, 6],
         {"kind": "activity: a movement between two uploaded balances (the first upload is the whole balance). close_pnl / close_re: the year-end close the warehouse synthesises in period 13 of a Period-end-balance year: each P&L account is reversed and the year's result moves to retained earnings. filler: a balance-sheet key with no movement this period, carried so its balance is restated to the new closing rate.",
          "in window": "1 when the period's first day is inside the entity's ownership window (Entities!F:G) and the entity consolidates line by line. 0 rows are dropped by the warehouse: shown here, amounts in scope are 0.",
          "rate": "closing (balance sheet), average (P&L), historical (share capital / premium, once the period is on or after the rate date), 1 for EUR. A Closing period uses its year's last Regular period's rates.",
          "retranslation": "konsolidat#257: cumulative local balance before this period x (this closing rate - previous closing rate), on balance-sheet, non-equity, closing-rate keys. Equity is never revalued.",
          "close adj P&L": "konsolidat#259: on a close row the reversal returns the key's translated year to zero: sum(local before) x rate - sum(translated before).",
          "close adj RE": "konsolidat#259: retained earnings takes the year's TRANSLATED result, so the close period has no CTA.",
          "translated": "local x rate + retranslation + close adjustments (100%).",
          "group amount": "translated x the group's share (konsolidat#204: a 70% subsidiary is carried at 70%).",
          "nci amount": "translated x (1 - share): the minority's share, computed per row, not in the tool's statements."})
    # structure: every movement row of every entity (in window or not) plus the warehouse's fillers (in-window keys only)
    struct = []
    for e in sorted(o.mov):
        for p in sorted(o.mov[e]):
            for (a, partner), (cents, src, is_close) in o.mov[e][p].items():
                kind = "close_re" if (is_close and a == "3300" and partner == "") else "close_pnl" if is_close else "activity"
                struct.append((e, a, partner, p, kind))
    for r in o.rows:
        if r["is_filler"]:
            struct.append((r["entity"], r["account"], r["partner"], r["period"], "filler"))
    struct.sort(key=lambda t: (t[0], t[1], t[2], ord_of[t[3]]))
    ent_periods = {e: sorted(o.mov[e]) for e in o.mov}
    # the entity's spine of consolidated periods, for "previous closing"
    cons_spine = {e: [p for p in ent_periods[e] if o.consolidated(e, p)] for e in o.mov}
    for i, (e, a, partner, p, kind) in enumerate(struct, 2):
        prev_p = None
        if kind in ("activity", "close_pnl", "close_re"):
            sp = sorted(set(ent_periods[e]))
            idx = sp.index(p)
            prev_p = sp[idx - 1] if idx > 0 else None
        else:
            sp = cons_spine[e]
            idx = sp.index(p)
            prev_p = sp[idx - 1] if idx > 0 else None
        put(ws, i, 1, e); put(ws, i, 2, pl(p)); put(ws, i, 3, '=INDEX(%s,MATCH(B%d,%s,0))' % (per_col("D"), i, PER)); put(ws, i, 4, a); put(ws, i, 5, partner)
        put(ws, i, 6, kind); put(ws, i, 7, pl(prev_p) if prev_p else "")
        key_now = 'A{r}&"|"&D{r}&"|"&E{r}&"|"&B{r}'.format(r=i)
        key_prev = 'A{r}&"|"&D{r}&"|"&E{r}&"|"&G{r}'.format(r=i)
        pnl_total_23 = 'SUMIFS(%s,%s,A{r},%s,"2023-12",%s,1)'.format(r=i) % (TBA, TBE, TBP, TBPL)
        bal_now = 'SUMIFS(%s,%s,%s)' % (TBA, TBK, key_now)
        bal_prev = 'SUMIFS(%s,%s,%s)' % (TBA, TBK, key_prev)
        bal_prev12 = 'SUMIFS(%s,%s,A{r}&"|"&D{r}&"|"&E{r}&"|2023-12")'.format(r=i) % (TBA, TBK)
        if kind == "activity":
            put(ws, i, 8, "=" + bal_now, fmt=NUM)
            # the previous balance: the previous uploaded balance, or the synthesised close balance when the previous spine period is 2023-13
            put(ws, i, 9, '=IF(G{r}="","0",IF(G{r}="2023-13",IF(AD{r}=1,0,{p12}+IF(AND(D{r}="3300",E{r}=""),{pnl},0)),{prev}))'.format(r=i, p12=bal_prev12, pnl=pnl_total_23, prev=bal_prev), fmt=NUM)
        elif kind == "close_pnl":
            put(ws, i, 8, 0, fmt=NUM); put(ws, i, 9, "=" + bal_prev, fmt=NUM)
        elif kind == "close_re":
            put(ws, i, 8, "=%s+%s" % (bal_prev, pnl_total_23), fmt=NUM); put(ws, i, 9, "=" + bal_prev, fmt=NUM)
        else:
            put(ws, i, 8, 0, fmt=NUM); put(ws, i, 9, 0, fmt=NUM)
        put(ws, i, 10, "=H%d-I%d" % (i, i), fmt=NUM)
        # window: first day between since and until, and the entity consolidates line by line
        put(ws, i, 11, '=IF(AND(INDEX(%s,MATCH(B{r},%s,0))>=INDEX(%s,MATCH(A{r},%s,0)),INDEX(%s,MATCH(B{r},%s,0))<=INDEX(%s,MATCH(A{r},%s,0)),INDEX(%s,MATCH(A{r},%s,0))="yes"),1,0)'.format(r=i)
            % (per_col("E"), PER, ent_col("F"), ENT, per_col("E"), PER, ent_col("G"), ENT, ent_col("H"), ENT))
        put(ws, i, 12, "=J%d*K%d" % (i, i), fmt=NUM)
        put(ws, i, 13, "=INDEX(%s,MATCH(A%d,%s,0))" % (ent_col("C"), i, ENT))
        put(ws, i, 14, "=" + ch_lookup("E", "D%d" % i))
        put(ws, i, 15, "=INDEX(%s,MATCH(B%d,%s,0))" % (per_col("G"), i, PER))
        hist = 'IF(INDEX(%s,MATCH(B{r},%s,0))>=INDEX(%s,MATCH(A{r},%s,0)),INDEX(%s,MATCH(A{r},%s,0)),{closing})'.format(r=i, closing=rate_formula("Closing", "M%d" % i, "O%d" % i)) % (per_col("E"), PER, HD, HE, HRt, HE)
        put(ws, i, 16, '=IF(M{r}="%s",1,IF(N{r}="historical",{hist},IF(N{r}="average",{avg},{clo})))'.format(r=i, hist=hist, avg=rate_formula("Average", "M%d" % i, "O%d" % i), clo=rate_formula("Closing", "M%d" % i, "O%d" % i)) % gcur, fmt=RATE)
        put(ws, i, 17, "=" + rate_formula("Closing", "M%d" % i, "O%d" % i), fmt=RATE)
        put(ws, i, 18, '=IF(G{r}="",Q{r},{prevc})'.format(r=i, prevc=rate_formula("Closing", "M%d" % i, 'INDEX(%s,MATCH(G%d,%s,0))' % (per_col("G"), i, PER))), fmt=RATE)
        # cumulative local before this row, within the key over rows in scope (the sheet is sorted by key then period)
        put(ws, i, 19, '=IF(AND(ROW()>2,AA%d=AA%d),S%d+L%d,0)' % (i, i - 1, i - 1, i - 1) if i > 2 else 0, fmt=NUM)
        put(ws, i, 20, "=IF(AE%d=1,S%d*(Q%d-R%d),0)*K%d" % (i, i, i, i, i), fmt=NUM)
        # close adjustments (konsolidat#259)
        key_year_before = 'SUMIFS(%s,{col},{val},%s,AF{r},%s,"<"&C{r})'
        rows_col = lambda c: "Rows!$%s$2:$%s$%d" % (c, c, len(struct) + 1)
        put(ws, i, 21, '=IF(F{r}="close_pnl",SUMIFS({J},{K},AA{r},{Y},AF{r},{C},"<"&C{r})*P{r}-SUMIFS({T0},{K},AA{r},{Y},AF{r},{C},"<"&C{r}),0)'.format(
            r=i, J=rows_col("L"), K=rows_col("AA"), Y=rows_col("AF"), C=rows_col("C"), T0=rows_col("AG")), fmt=NUM)
        put(ws, i, 22, '=IF(F{r}="close_re",SUMIFS({J},{A},A{r},{B},B{r},{F},"close_pnl")*P{r}-SUMIFS({T0},{A},A{r},{B},B{r},{F},"close_pnl")-SUMIFS({U},{A},A{r},{B},B{r},{F},"close_pnl"),0)'.format(
            r=i, J=rows_col("L"), A=rows_col("A"), B=rows_col("B"), F=rows_col("F"), T0=rows_col("AG"), U=rows_col("U")), fmt=NUM)
        put(ws, i, 23, "=(L%d*P%d+T%d+U%d+V%d)" % (i, i, i, i, i), fmt=NUM)
        put(ws, i, 24, "=INDEX(%s,MATCH(A%d,%s,0))" % (ent_col("I"), i, ENT), fmt="0%")
        put(ws, i, 25, "=W%d*X%d" % (i, i), fmt=NUM)
        put(ws, i, 26, "=W%d*(1-X%d)*K%d" % (i, i, i), fmt=NUM)
        put(ws, i, 27, '=A%d&"|"&D%d&"|"&E%d' % (i, i, i))
        put(ws, i, 28, "=" + ch_lookup("H", "D%d" % i)); put(ws, i, 29, "=" + ch_lookup("F", "D%d" % i)); put(ws, i, 30, "=" + ch_lookup("G", "D%d" % i))
        put(ws, i, 31, "=" + ch_lookup("J", "D%d" % i)); put(ws, i, 32, "=INDEX(%s,MATCH(B%d,%s,0))" % (per_col("B"), i, PER))
        put(ws, i, 33, "=L%d*P%d+T%d" % (i, i, i), fmt=NUM)   # AG: translated before close adjustments
    ws.cell(row=1, column=33, value="translated before close adj").font = F_HEAD
    ws.cell(row=1, column=33).fill = FILL_HEAD
    n_rows = len(struct) + 1
    RW = lambda c: "Rows!$%s$2:$%s$%d" % (c, c, n_rows)

    # ------------------------------------------------------------------ CTA
    ws = wb.create_sheet("CTA")
    head(ws, 1, ["entity"] + [pl(p) for p in spine] + ["cumulative at 2024-12"], [8] + [13] * (len(spine) + 1),
         {"entity": "gold_fx_revaluation: CTA of an entity-period = -(sum of its group amounts). The plug that keeps the translated balance sheet in balance. 0 for EUR entities and in the close period."})
    cons_ents = [e for e in ent_codes if d["entities"][e]["method"] == "full"]
    for i, e in enumerate(cons_ents, 2):
        put(ws, i, 1, e)
        for j, p in enumerate(spine, 2):
            put(ws, i, j, '=-SUMIFS(%s,%s,$A%d,%s,%s$1)' % (RW("Y"), RW("A"), i, RW("B"), L(j)), fmt=NUM)
        put(ws, i, len(spine) + 2, "=SUM(B%d:%s%d)" % (i, L(len(spine) + 1), i), fmt=NUM)
    n_cta = len(cons_ents) + 1

    # ------------------------------------------------------------------ IC
    ws = wb.create_sheet("IC")
    ic_cols = ["period", "ordinal", "entity a", "account a", "entity b", "account b", "basis", "event", "pair",
               "local a", "local b", "translated a", "translated b", "group a", "group b", "share a", "share b", "matched", "residual a", "residual b", "difference", "cause", "status",
               "m_a", "m_b", "n_a", "n_b", "d_a", "d_b", "post m_a", "post n_a", "post n_b", "post d_a", "post d_b",
               "to account a", "to account b", "to NCI account", "to difference account", "NCI reclass account (IFRS view)", "NCI entity"]
    head(ws, 1, ic_cols, [8, 6, 7, 8, 7, 8, 9, 7, 14] + [12] * 14 + [11] * 11 + [14, 8],
         {"basis": "balance: a balance-sheet pair compares cumulative translated amounts to date; movement: a P&L pair compares the period.",
          "event": "joined: the first period both sides are in the group; left: the period after one side left (everything eliminated is reversed).",
          "share a": "group amount / translated amount of the side: the share it is carried at (1.0, or 0.7 for ABSE).",
          "matched": "the offsetting amount both sides agree on at 100%: min(|a|,|b|) when the signs differ.",
          "cause": "none: within half a cent. fx: the currencies differ, or the local amounts agree. booking: the local amounts disagree.",
          "m_a": "the matched amount eliminated at the lower of the two shares (group view). n_a / n_b: the better-owned side's extra share, moved to the NCI account and attributed to the other side (decision 12). d_a / d_b: the residual at the side's share, booked to the group's intercompany difference account.",
          "post m_a": "what this period posts: for a balance pair the change against the previous row of the pair; a movement pair posts the period's figure. Half a cent or less posts nothing.",
          "to account a": "the elimination legs by account: account a gets post m_a + post n_a + post d_a; account b gets -post m_a + post n_b + post d_b; the NCI account gets -(post n_a + post n_b); the difference account gets -(post d_a + post d_b).",
          "NCI reclass account (IFRS view)": "Where the NCI leg would go under IFRS 10 (100% consolidation): the partly owned side's own account, instead of the NCI account."})
    recon = sorted(o.recon, key=lambda r: (r["entity_a"], r["account_a"], r["entity_b"], r["account_b"], ord_of[r["period"]]))
    tol = d["policy"]["ic_difference_tolerance"]
    for i, r in enumerate(recon, 2):
        p = r["period"]
        put(ws, i, 1, pl(p)); put(ws, i, 2, '=INDEX(%s,MATCH(A%d,%s,0))' % (per_col("D"), i, PER))
        put(ws, i, 3, r["entity_a"]); put(ws, i, 4, r["account_a"]); put(ws, i, 5, r["entity_b"]); put(ws, i, 6, r["account_b"])
        put(ws, i, 7, r["basis"]); put(ws, i, 8, r["event"]); put(ws, i, 9, '=C%d&"|"&D%d&"|"&E%d&"|"&F%d' % (i, i, i, i))
        def side(colsrc, ent, acc, partner):
            per_sum = 'SUMIFS({v},{A},{e},{B},$A{r},{D},{a},{E},{p})'.format(v=RW(colsrc), A=RW("A"), e=ent, B=RW("B"), r=i, D=RW("D"), a=acc, E=RW("E"), p=partner)
            cum_sum = 'SUMIFS({v},{A},{e},{C},"<="&$B{r},{D},{a},{E},{p})'.format(v=RW(colsrc), A=RW("A"), e=ent, C=RW("C"), r=i, D=RW("D"), a=acc, E=RW("E"), p=partner)
            return '=IF($G{r}="movement",{per},IF($H{r}="left",0,{cum}))'.format(r=i, per=per_sum, cum=cum_sum)
        put(ws, i, 10, side("L", "C%d" % i, "D%d" % i, "E%d" % i), fmt=NUM)
        put(ws, i, 11, side("L", "E%d" % i, "F%d" % i, "C%d" % i), fmt=NUM)
        put(ws, i, 12, side("W", "C%d" % i, "D%d" % i, "E%d" % i).replace("SUMIFS(%s" % RW("W"), "SUMIFS(%s" % RW("W")), fmt=NUM)
        put(ws, i, 13, side("W", "E%d" % i, "F%d" % i, "C%d" % i), fmt=NUM)
        put(ws, i, 14, side("Y", "C%d" % i, "D%d" % i, "E%d" % i), fmt=NUM)
        put(ws, i, 15, side("Y", "E%d" % i, "F%d" % i, "C%d" % i), fmt=NUM)
        put(ws, i, 16, "=IF(ABS(L%d)>=0.005,N%d/L%d,1)" % (i, i, i), fmt="0.0000"); put(ws, i, 17, "=IF(ABS(M%d)>=0.005,O%d/M%d,1)" % (i, i, i), fmt="0.0000")
        put(ws, i, 18, "=IF(L%d*M%d<0,MIN(ABS(L%d),ABS(M%d)),0)" % (i, i, i, i), fmt=NUM)
        put(ws, i, 19, "=L%d-SIGN(L%d)*R%d" % (i, i, i), fmt=NUM); put(ws, i, 20, "=M%d-SIGN(M%d)*R%d" % (i, i, i), fmt=NUM)
        put(ws, i, 21, "=L%d+M%d" % (i, i), fmt=NUM)
        cur_a = 'INDEX(%s,MATCH(C%d,%s,0))' % (ent_col("C"), i, ENT); cur_b = 'INDEX(%s,MATCH(E%d,%s,0))' % (ent_col("C"), i, ENT)
        put(ws, i, 22, '=IF(ABS(U{r})<0.005,"none",IF({ca}<>{cb},"fx",IF(ABS(J{r}+K{r})>=0.005,"booking","fx")))'.format(r=i, ca=cur_a, cb=cur_b))
        put(ws, i, 23, '=IF(V{r}="none","matched",IF(AND(V{r}="fx",NOT(AND(G{r}="balance",{ca}<>{cb}))),"fx_difference",IF(ABS(U{r})<={tol},"within_tolerance","over_tolerance")))'.format(r=i, ca=cur_a, cb=cur_b, tol=tol))
        put(ws, i, 24, "=-SIGN(L%d)*R%d*MIN(P%d,Q%d)" % (i, i, i, i), fmt=NUM); put(ws, i, 25, "=-SIGN(M%d)*R%d*MIN(P%d,Q%d)" % (i, i, i, i), fmt=NUM)
        put(ws, i, 26, "=IF(P%d>Q%d,-SIGN(L%d)*R%d*(P%d-Q%d),0)" % (i, i, i, i, i, i), fmt=NUM); put(ws, i, 27, "=IF(Q%d>P%d,-SIGN(M%d)*R%d*(Q%d-P%d),0)" % (i, i, i, i, i, i), fmt=NUM)
        put(ws, i, 28, "=-S%d*P%d" % (i, i), fmt=NUM); put(ws, i, 29, "=-T%d*Q%d" % (i, i), fmt=NUM)
        prev_same = '(ROW()>2)*(I%d=I%d)' % (i, i - 1) if i > 2 else "0"
        for k, (col, src) in enumerate((("AD", "X"), ("AE", "Z"), ("AF", "AA"), ("AG", "AB"), ("AH", "AC"))):
            prev_ref = "%s%d" % (src, i - 1) if i > 2 else "0"
            f = '=IF(ABS({s}{r}-IF(AND($G{r}="balance",{same}),{prev},0))<0.005,0,{s}{r}-IF(AND($G{r}="balance",{same}),{prev},0))'.format(
                s=src, r=i, same=prev_same if i > 2 else "FALSE", prev=prev_ref)
            put(ws, i, 30 + k, f, fmt=NUM)
        put(ws, i, 35, "=AD%d+AE%d+AG%d" % (i, i, i), fmt=NUM); put(ws, i, 36, "=-AD%d+AF%d+AH%d" % (i, i, i), fmt=NUM)
        put(ws, i, 37, "=-(AE%d+AF%d)" % (i, i), fmt=NUM); put(ws, i, 38, "=-(AG%d+AH%d)" % (i, i), fmt=NUM)
        put(ws, i, 39, '=IF(Q%d<P%d,F%d,IF(P%d<Q%d,D%d,""))' % (i, i, i, i, i, i))
        put(ws, i, 40, '=IF(Q%d<P%d,E%d,IF(P%d<Q%d,C%d,""))' % (i, i, i, i, i, i))
    n_ic = len(recon) + 1
    IC = lambda c: "IC!$%s$2:$%s$%d" % (c, c, n_ic)

    # ------------------------------------------------------------------ Acquisition
    ws = wb.create_sheet("Acquisition")
    ws.column_dimensions["A"].width = 34; ws.column_dimensions["B"].width = 16; ws.column_dimensions["C"].width = 16; ws.column_dimensions["D"].width = 60
    acq = d["acquisition"]
    put(ws, 1, 1, "Business Combination ACQ-AQBIKE-ABCZ-%s: 100%% of Aquila Kola s.r.o. (CZK) for cash" % acq["date"], F_TITLE)
    params = [("acquired entity", acq["entity"], None), ("acquisition date", dt.date.fromisoformat(acq["date"]), "yyyy-mm-dd"),
              ("acquisition period", pl(acq["period"]), None), ("last period before (opening balance sheet)", pl(acq["pre_period"]), None),
              ("consideration (EUR, cash)", float(acq["consideration_eur"]), NUM), ("share acquired", 1.0, "0%"),
              ("fair value step-up on 1113 (CZK)", float(acq["fva_czk"]), NUM), ("NCI measurement", "partial (no NCI at 100%)", None)]
    for i, (k, v, fmt) in enumerate(params, 3):
        put(ws, i, 1, k, F_BOLD); put(ws, i, 2, v, F_INPUT, fmt)
    put(ws, 11, 1, "closing rate CZK->EUR, acquisition period", F_BOLD)
    put(ws, 11, 2, "=" + rate_formula("Closing", '"CZK"', "B5"), fmt=RATE)
    put(ws, 11, 4, "Every line of the journal translates at the acquisition period's governed Closing rate.")
    put(ws, 13, 1, "Acquired balance sheet at 31 May 2024 (konsol: Business Combination lines; book amounts CZK, Dr +, Cr -)", F_H2)
    head(ws, 14, ["account", "book amount (CZK)", "fair value adjustment (CZK)", "note", "is_equity"], None)
    ws.freeze_panes = None
    ab_rows = acq["acquired_balances"]
    for i, l in enumerate(ab_rows, 15):
        put(ws, i, 1, l["main_account"], F_INPUT); put(ws, i, 2, float(l["book_amount"]), F_INPUT, NUM)
        put(ws, i, 3, float(l["fair_value_adjustment"] or 0), F_INPUT, NUM); put(ws, i, 4, l["note"])
        put(ws, i, 5, "=" + ch_lookup("F", "A%d" % i))
    ab_end = 14 + len(ab_rows)
    put(ws, ab_end + 1, 1, "check: the lines net to zero", F_BOLD); put(ws, ab_end + 1, 2, "=SUM(B15:B%d)" % ab_end, fmt=NUM)
    j0 = ab_end + 3
    put(ws, j0, 1, "The acquisition journal (EUR), as gold_business_combination_journal posts it in %s" % pl(acq["period"]), F_H2)
    head(ws, j0 + 1, ["account", "amount (EUR, Dr +)", "role", "rule"], None)
    ws.freeze_panes = None
    acq_lines = []
    r = j0 + 2
    # line 0: opening balances through the period before, at the acquisition closing rate (gold_trial_balance = Rows!J, in window or not)
    pre_ord = ord_of[acq["pre_period"]]
    open_accts = sorted({l["account"] for l in o.acq_lines if l["role"] == "opening_balance" and l["account"] != "3300"} | ({"3300"} if any(l["role"] == "opening_balance" and l["account"] == "3300" for l in o.acq_lines) else set()))
    first_open = r
    for a in open_accts:
        if a == "3300":
            continue
        put(ws, r, 1, a); put(ws, r, 2, '=SUMIFS(%s,%s,$B$3,%s,A%d,%s,"<="&%d)*$B$11' % (RW("J"), RW("A"), RW("D"), r, RW("C"), pre_ord), fmt=NUM)
        put(ws, r, 3, "opening_balance"); put(ws, r, 4, "line 0: the entity's cumulative balance-sheet movements through %s x closing rate; the window starts at the acquisition so the entity layer never carries this position" % pl(acq["pre_period"]))
        r += 1
    put(ws, r, 1, "3300"); put(ws, r, 2, "=-SUM(B%d:B%d)" % (first_open, r - 1), fmt=NUM); put(ws, r, 3, "opening_balance")
    put(ws, r, 4, "line 0 balancing: the result still open in the P&L at 31 May is pre-acquisition equity, so it goes to retained earnings"); r += 1
    first_eq = r
    for i, l in enumerate(ab_rows, 15):
        if o.is_equity(l["main_account"]):
            put(ws, r, 1, "=A%d" % i); put(ws, r, 2, "=-B%d*$B$11" % i, fmt=NUM); put(ws, r, 3, "equity_eliminated")
            put(ws, r, 4, "line (1): -(book amount) of every acquired-balance row the chart types Equity, 100%"); r += 1
    last_eq = r - 1
    put(ws, r, 1, d["policy"]["fair_value_adjustment_account"]); put(ws, r, 2, "=SUM(C15:C%d)*$B$11" % ab_end, fmt=NUM); put(ws, r, 3, "fva")
    put(ws, r, 4, "line 101: Dr fair_value_adjustment_account by the step-ups (100%)"); fva_r = r; r += 1
    put(ws, r, 1, d["policy"]["goodwill_account"]); put(ws, r, 2, "=MAX(0,$B$7-(SUM(B%d:B%d)+B%d))" % (first_eq, last_eq, fva_r), fmt=NUM); put(ws, r, 3, "goodwill")
    put(ws, r, 4, "line 102: consideration (+ capitalised costs 0 + NCI 0) - (net assets at book + fair value adjustments); IFRS 3.32"); gw_r = r; r += 1
    put(ws, r, 1, d["policy"]["investment_account"]); put(ws, r, 2, "=-$B$7", fmt=NUM); put(ws, r, 3, "investment")
    put(ws, r, 4, "line 103: Cr investment_account by the consideration: the parent's Dr 1141 in its own books is eliminated"); r += 1
    for kind, amount in acq["costs_eur"]:
        put(ws, r, 1, d["policy"]["acquisition_costs_account"]); put(ws, r, 2, float(amount), F_INPUT, NUM); put(ws, r, 3, "costs"); put(ws, r, 4, "%s fees, expensed (policy: Expense; IFRS 3.53)" % kind); r += 1
        put(ws, r, 1, d["policy"]["disposal_proceeds_account"]); put(ws, r, 2, "=-B%d" % (r - 1), fmt=NUM); put(ws, r, 3, "costs_settlement"); put(ws, r, 4, "the settlement side: the parent parked the cost on the Deal Settlement Account"); r += 1
    acq_first, acq_last = j0 + 2, r - 1
    put(ws, r, 1, "check: the journal sums to zero", F_BOLD); put(ws, r, 2, "=SUM(B%d:B%d)" % (acq_first, acq_last), fmt=NUM); ws.cell(row=r, column=2).fill = FILL_CHECK
    ACQ_A, ACQ_B = "Acquisition!$A$%d:$A$%d" % (acq_first, acq_last), "Acquisition!$B$%d:$B$%d" % (acq_first, acq_last)
    acq_gw_cell = "Acquisition!$B$%d" % gw_r

    # ------------------------------------------------------------------ Disposal
    ws = wb.create_sheet("Disposal")
    ws.column_dimensions["A"].width = 34; ws.column_dimensions["B"].width = 16; ws.column_dimensions["C"].width = 16; ws.column_dimensions["D"].width = 60
    dsp = d["disposal"]
    put(ws, 1, 1, "Business Disposal DSP-AQBIKE-ABDK-%s: 100%% of Aquila Cykler Danmark A/S (DKK) for cash" % dsp["date"], F_TITLE)
    for i, (k, v, fmt) in enumerate([("disposed entity", dsp["entity"], None), ("disposal date", dt.date.fromisoformat(dsp["date"]), "yyyy-mm-dd"),
                                     ("disposal period", pl(dsp["period"]), None), ("proceeds (EUR, cash)", float(dsp["proceeds_eur"]), NUM), ("share disposed", 1.0, "0%")], 3):
        put(ws, i, 1, k, F_BOLD); put(ws, i, 2, v, F_INPUT, fmt)
    put(ws, 9, 1, "closing rate DKK->EUR, disposal period", F_BOLD); put(ws, 9, 2, "=" + rate_formula("Closing", '"DKK"', "B5"), fmt=RATE)
    j0 = 11
    put(ws, j0, 1, "The disposal journal (EUR), as gold_business_disposal_journal posts it in %s" % pl(dsp["period"]), F_H2)
    head(ws, j0 + 1, ["account", "amount (EUR, Dr +)", "role", "rule"], None)
    ws.freeze_panes = None
    r = j0 + 2
    dsp_ord = ord_of[dsp["period"]]
    der_accts = [l["account"] for l in o.dsp_lines if l["role"] == "derecognised"]
    for a in der_accts:
        put(ws, r, 1, a); put(ws, r, 2, '=-SUMIFS(%s,%s,$B$3,%s,A%d,%s,"<="&%d)*$B$9' % (RW("J"), RW("A"), RW("D"), r, RW("C"), dsp_ord), fmt=NUM)
        put(ws, r, 3, "derecognised"); put(ws, r, 4, "line 0: -(cumulative balance at the disposal period end) x closing rate, every non-equity balance-sheet account, 100%. Equity is not touched (IFRS 10.B98)"); r += 1
    put(ws, r, 1, d["policy"]["goodwill_account"]); put(ws, r, 2, 0, fmt=NUM); put(ws, r, 3, "goodwill"); put(ws, r, 4, "line 101: -(goodwill the acquisition journal booked for this entity): none, ABDK was founded, not bought"); r += 1
    put(ws, r, 1, d["policy"]["fair_value_adjustment_account"]); put(ws, r, 2, 0, fmt=NUM); put(ws, r, 3, "fva"); put(ws, r, 4, "line 102: -(fair value adjustments booked at acquisition): none"); r += 1
    put(ws, r, 1, "CTA"); put(ws, r, 2, '=-SUM(INDEX(CTA!$B$2:$%s$%d,MATCH($B$3,CTA!$A$2:$A$%d,0),0))' % (L(len(spine) + 1), n_cta, n_cta), fmt=NUM); put(ws, r, 3, "cta")
    put(ws, r, 4, "line 103: -(the entity's accumulated CTA in this group through the disposal period): IAS 21.48 recycling, the counterpart is inside the gain"); r += 1
    put(ws, r, 1, d["policy"]["nci_account"]); put(ws, r, 2, 0, fmt=NUM); put(ws, r, 3, "nci"); put(ws, r, 4, "line 104: -(NCI the acquisition credited): none"); r += 1
    put(ws, r, 1, d["policy"]["disposal_proceeds_account"]); put(ws, r, 2, "=$B$6", fmt=NUM); put(ws, r, 3, "proceeds"); put(ws, r, 4, "line 110: Dr the Deal Settlement Account; the parent parked the cash received there"); r += 1
    put(ws, r, 1, d["policy"]["disposal_gain_loss_account"]); put(ws, r, 2, "=-SUM(B%d:B%d)" % (j0 + 2, r - 1), fmt=NUM); put(ws, r, 3, "gain_loss")
    put(ws, r, 4, "line 199: the balancing line; a credit is a gain"); gain_r = r; r += 1
    dsp_first, dsp_last = j0 + 2, r - 1
    put(ws, r, 1, "check: the journal sums to zero", F_BOLD); put(ws, r, 2, "=SUM(B%d:B%d)" % (dsp_first, dsp_last), fmt=NUM); ws.cell(row=r, column=2).fill = FILL_CHECK
    put(ws, r + 1, 1, "gain on disposal (credit positive)", F_BOLD); put(ws, r + 1, 2, "=-B%d" % gain_r, fmt=NUM)
    DSP_A, DSP_B = "Disposal!$A$%d:$A$%d" % (dsp_first, dsp_last), "Disposal!$B$%d:$B$%d" % (dsp_first, dsp_last)
    dsp_gain_cell = "Disposal!$B$%d" % (r + 1)

    # ------------------------------------------------------------------ EquityMethod
    ws = wb.create_sheet("EquityMethod")
    head(ws, 1, ["period", "associate", "share", "currency", "result (local, Dr +)", "average rate", "EQ_INCOME (EUR)", "EQ_INVEST (EUR)"], [9, 10, 7, 9, 18, 12, 16, 16],
         {"result (local, Dr +)": "The associate's P&L movements of the period (gold_trial_balance), including the synthesised year-end close in 2023-13.",
          "EQ_INCOME (EUR)": "share of result x average rate (a profit is a credit, negative). EQ_INVEST is the debit counterpart. Entries at or below 0.01 are not posted."})
    assoc = [e for e in ent_codes if d["entities"][e]["method"] == "equity"]
    r = 2
    for e in assoc:
        for p in sorted(o.mov[e]):
            if not o.in_window(e, p):
                continue
            put(ws, r, 1, pl(p)); put(ws, r, 2, e); put(ws, r, 3, "=INDEX(%s,MATCH(B%d,%s,0))" % (ent_col("D"), r, ENT), fmt="0%")
            put(ws, r, 4, "=INDEX(%s,MATCH(B%d,%s,0))" % (ent_col("C"), r, ENT))
            put(ws, r, 5, "=SUMIFS(%s,%s,B%d,%s,A%d,%s,1)" % (RW("J"), RW("A"), r, RW("B"), r, RW("AD")), fmt=NUM)
            put(ws, r, 6, "=" + rate_formula("Average", "D%d" % r, 'INDEX(%s,MATCH(A%d,%s,0))' % (per_col("G"), r, PER)), fmt=RATE)
            put(ws, r, 7, "=IF(ABS(E%d*C%d*F%d)<=0.01,0,E%d*C%d*F%d)" % (r, r, r, r, r, r), fmt=NUM); put(ws, r, 8, "=-G%d" % r, fmt=NUM)
            r += 1
    n_eq = r - 1
    EQ = lambda c: "EquityMethod!$%s$2:$%s$%d" % (c, c, max(n_eq, 2))

    # ------------------------------------------------------------------ Topside
    ws = wb.create_sheet("Topside")
    head(ws, 1, ["journal", "period", "entity", "account", "debit (EUR)", "credit (EUR)", "amount (Dr +)", "description"], [14, 9, 8, 9, 14, 14, 14, 60],
         {"journal": "Consolidation Journal CJ-OPEN-2023 (Consolidation_Journals / CJ_Lines in the master workbook), approved: the first consolidation's elimination of the parent's investments in its founded subsidiaries against their share capital and premium, each at the group's share and the historical rate."})
    for i, l in enumerate(d["opening_journal"], 2):
        put(ws, i, 1, l["journal_ref"]); put(ws, i, 2, "2023-12"); put(ws, i, 3, l["data_area_id"]); put(ws, i, 4, l["main_account"])
        put(ws, i, 5, float(l["debit_amount"] or 0), F_INPUT, NUM); put(ws, i, 6, float(l["credit_amount"] or 0), F_INPUT, NUM)
        put(ws, i, 7, "=E%d-F%d" % (i, i), fmt=NUM); put(ws, i, 8, l["description"])
    n_top = len(d["opening_journal"]) + 1
    put(ws, n_top + 1, 4, "check", F_BOLD); put(ws, n_top + 1, 7, "=SUM(G2:G%d)" % n_top, fmt=NUM); ws.cell(row=n_top + 1, column=7).fill = FILL_CHECK
    TOP = lambda c: "Topside!$%s$2:$%s$%d" % (c, c, n_top)

    # ------------------------------------------------------------------ ConsolTB
    ws = wb.create_sheet("ConsolTB")
    ct_cols = ["period", "ordinal", "account", "name", "statement", "entity layer", "IC eliminations", "CTA", "topside", "acquisition", "disposal", "equity method",
               "TOTAL (tool)", "Python replica", "diff (must be 0)", "NCI share (minority, per row)", "IFRS reclass of NCI legs", "TOTAL (IFRS 100% view)"]
    head(ws, 1, ct_cols, [8, 6, 9, 40, 9, 14, 14, 13, 13, 13, 13, 13, 15, 15, 12, 15, 14, 15],
         {"entity layer": "sum of the group amounts of the entity rows (Rows!Y) for the period and account",
          "IC eliminations": "the elimination legs of sheet IC for the period and account (group view)",
          "Python replica": "aquila_bike_offline.py's figure for the same cell (static): the independent check that the formulas follow the warehouse's rules",
          "NCI share (minority, per row)": "sum of Rows!Z (translated x (1 - share)) for the period and account: what the tool computes but does not show",
          "IFRS reclass of NCI legs": "under IFRS 10 the NCI legs of the intercompany eliminations fall on the partly owned side's own account, not on the NCI account",
          "TOTAL (IFRS 100% view)": "tool total + minority share + reclass: every entity at 100%; the NCI line of the IFRS balance sheet is the minority's share of net assets (sheet Statements)"})
    all_accts = chart_codes + ["CTA", "EQ_INCOME", "EQ_INVEST"]
    exp_fctb = {}
    for x in exp["fctb"]:
        exp_fctb[(x["period"], x["account"])] = exp_fctb.get((x["period"], x["account"]), 0.0) + x["amount"]
    r = 2
    ct_first = r
    for p in spine:
        for a in all_accts:
            put(ws, r, 1, pl(p)); put(ws, r, 2, ord_of[p]); put(ws, r, 3, a); put(ws, r, 4, "=" + ch_lookup("B", "C%d" % r)); put(ws, r, 5, "=" + ch_lookup("D", "C%d" % r))
            put(ws, r, 6, "=SUMIFS(%s,%s,$A%d,%s,$C%d)" % (RW("Y"), RW("B"), r, RW("D"), r), fmt=NUM)
            put(ws, r, 7, '=SUMIFS({ta},{p},$A{r},{aa},$C{r})+SUMIFS({tb},{p},$A{r},{ab},$C{r})+IF($C{r}="{nci}",SUMIFS({tn},{p},$A{r}),0)+IF($C{r}="{dif}",SUMIFS({td},{p},$A{r}),0)'.format(
                ta=IC("AI"), tb=IC("AJ"), tn=IC("AK"), td=IC("AL"), p=IC("A"), aa=IC("D"), ab=IC("F"), r=r, nci=d["policy"]["nci_account"], dif=d["policy"]["ic_difference_account"]), fmt=NUM)
            put(ws, r, 8, '=IF($C{r}="CTA",SUM(INDEX(CTA!$B$2:${lc}${n},0,MATCH($A{r},CTA!$B$1:${lc}$1,0))),0)'.format(r=r, lc=L(len(spine) + 1), n=n_cta), fmt=NUM)
            put(ws, r, 9, "=SUMIFS(%s,%s,$A%d,%s,$C%d)" % (TOP("G"), TOP("B"), r, TOP("D"), r), fmt=NUM)
            put(ws, r, 10, '=IF($A{r}="{ap}",SUMIFS({b},{a},$C{r}),0)'.format(r=r, ap=pl(acq["period"]), b=ACQ_B, a=ACQ_A), fmt=NUM)
            put(ws, r, 11, '=IF($A{r}="{dp}",SUMIFS({b},{a},$C{r}),0)'.format(r=r, dp=pl(dsp["period"]), b=DSP_B, a=DSP_A), fmt=NUM)
            put(ws, r, 12, '=IF($C{r}="EQ_INCOME",SUMIFS({g},{p},$A{r}),IF($C{r}="EQ_INVEST",SUMIFS({h},{p},$A{r}),0))'.format(r=r, g=EQ("G"), h=EQ("H"), p=EQ("A")), fmt=NUM)
            put(ws, r, 13, "=SUM(F%d:L%d)" % (r, r), F_BOLD, NUM)
            put(ws, r, 14, round(exp_fctb.get((pl(p), a), 0.0), 6), F_INPUT, NUM)
            put(ws, r, 15, "=ROUND(M%d-N%d,2)" % (r, r), fmt=NUM); ws.cell(row=r, column=15).fill = FILL_CHECK
            put(ws, r, 16, "=SUMIFS(%s,%s,$A%d,%s,$C%d)" % (RW("Z"), RW("B"), r, RW("D"), r), fmt=NUM)
            put(ws, r, 17, '=SUMIFS({tn},{p},$A{r},{ra},$C{r})+IF($C{r}="{nci}",-SUMIFS({tn},{p},$A{r}),0)'.format(tn=IC("AK"), p=IC("A"), ra=IC("AM"), r=r, nci=d["policy"]["nci_account"]), fmt=NUM)
            put(ws, r, 18, "=M%d+P%d+Q%d" % (r, r, r), F_BOLD, NUM)
            r += 1
    ct_last = r - 1
    CT = lambda c: "ConsolTB!$%s$%d:$%s$%d" % (c, ct_first, c, ct_last)
    put(ws, r + 1, 4, "checks over every period", F_BOLD)
    put(ws, r + 2, 4, "sum of every layer (must be 0)"); put(ws, r + 2, 13, "=ROUND(SUM(M%d:M%d),2)" % (ct_first, ct_last), fmt=NUM); ws.cell(row=r + 2, column=13).fill = FILL_CHECK
    put(ws, r + 3, 4, "largest difference to the Python replica"); put(ws, r + 3, 15, "=MAX(MAX(O%d:O%d),-MIN(O%d:O%d))" % (ct_first, ct_last, ct_first, ct_last), fmt=NUM); ws.cell(row=r + 3, column=15).fill = FILL_CHECK
    put(ws, r + 4, 4, "sum of the IFRS view (must be the minority's share of net assets movements, i.e. 0 after the NCI line)"); put(ws, r + 4, 18, "=ROUND(SUM(R%d:R%d)-SUM(P%d:P%d),2)" % (ct_first, ct_last, ct_first, ct_last), fmt=NUM)
    ct_check_rows = (r + 2, r + 3)

    # ------------------------------------------------------------------ Statements
    ws = wb.create_sheet("Statements")
    ws.column_dimensions["A"].width = 46
    for j in range(2, len(spine) + 4):
        ws.column_dimensions[L(j)].width = 14
    put(ws, 1, 1, "Consolidated statements of the Aquila Bike Group (EUR)", F_TITLE)
    put(ws, 2, 1, "Credit-positive presentation: revenue, profit and equity positive; costs and assets as the reader expects. Tool view = what konsolidat shows (subsidiaries at the group's share). IFRS view = every subsidiary at 100% with the minority as an NCI line.")
    ws.cell(row=2, column=1).alignment = WRAP; ws.row_dimensions[2].height = 30
    hdr = ["line"] + [pl(p) for p in spine] + ["FY2024"]
    fy_cols = [j for j, p in enumerate(spine, 2) if p[0] == 2024]

    def sum_line(row, pred_formula_builder, sign=1, cumulative=False, col_letter="M"):
        for j, p in enumerate(spine, 2):
            cond = '%s,"<="&%d' % (CT("B"), ord_of[p]) if cumulative else '%s,%s$%d' % (CT("A"), L(j), row_hdr)
            put(ws, row, j, "=%d*SUMIFS(%s,%s,%s)" % (sign, CT(col_letter), cond, pred_formula_builder), fmt=NUM)
        if not cumulative:
            put(ws, row, len(spine) + 2, "=SUM(%s%d:%s%d)" % (L(fy_cols[0]), row, L(fy_cols[-1]), row), F_BOLD, NUM)

    def pnl_block(top, title, col_letter):
        nonlocal row_hdr
        put(ws, top, 1, title, F_H2)
        row_hdr = top + 1
        head(ws, row_hdr, hdr, None)
        ws.freeze_panes = None
        lines = [("Revenue", '%s,"4*"' % CT("C"), -1), ("Cost of sales", '%s,"5*"' % CT("C"), -1), ("Operating expenses", '%s,"6*"' % CT("C"), -1),
                 ("Financial items", '%s,"7*"' % CT("C"), -1), ("Share of result of associates (EQ_INCOME)", '%s,"EQ_INCOME"' % CT("C"), -1),
                 ("Income taxes", '%s,"8*"' % CT("C"), -1)]
        rr = row_hdr + 1
        first = rr
        for name, pred, sign in lines:
            put(ws, rr, 1, name); sum_line(rr, pred, sign, col_letter=col_letter); rr += 1
        put(ws, rr, 1, "Net result for the period", F_BOLD)
        for j in range(2, len(spine) + 3):
            put(ws, rr, j, "=SUM(%s%d:%s%d)" % (L(j), first, L(j), rr - 1), F_BOLD, NUM)
        return rr

    def bs_block(top, title, col_letter, nci_line=False, owner_cols=None):
        owner_cols = owner_cols or [col_letter]
        nonlocal row_hdr
        put(ws, top, 1, title, F_H2)
        row_hdr = top + 1
        head(ws, row_hdr, hdr[:-1], None)
        ws.freeze_panes = None
        rr = row_hdr + 1
        first = rr
        put(ws, rr, 1, "Assets (1xxx, EQ_INVEST)"); sum_line(rr, '%s,"1*"' % CT("C"), 1, True, col_letter)
        for j, p in enumerate(spine, 2):
            ws.cell(row=rr, column=j).value = ws.cell(row=rr, column=j).value + '+SUMIFS(%s,%s,"<="&%d,%s,"EQ_INVEST")' % (CT(col_letter), CT("B"), ord_of[p], CT("C"))
        rr += 1
        put(ws, rr, 1, "Liabilities (2xxx)"); sum_line(rr, '%s,"2*"' % CT("C"), -1, True, col_letter); rr += 1
        put(ws, rr, 1, "Net assets", F_BOLD)
        for j in range(2, len(spine) + 2):
            put(ws, rr, j, "=%s%d-%s%d" % (L(j), first, L(j), first + 1), F_BOLD, NUM)
        na = rr; rr += 1
        put(ws, rr, 1, "Share capital, premium, reserves, retained earnings (3xxx)" + (" - owners" if nci_line else ""))
        for j, p in enumerate(spine, 2):
            put(ws, rr, j, "=-(" + "+".join('SUMIFS(%s,%s,"<="&%d,%s,"3*")' % (CT(c), CT("B"), ord_of[p], CT("C")) for c in owner_cols) + ")", fmt=NUM)
        rr += 1
        put(ws, rr, 1, "Currency translation adjustment (CTA)"); sum_line(rr, '%s,"CTA"' % CT("C"), -1, True, "M"); rr += 1
        put(ws, rr, 1, "Result of the year not yet closed (P&L accounts)" + (" - owners" if nci_line else ""))
        for j, p in enumerate(spine, 2):
            put(ws, rr, j, "=-(" + "+".join('SUMIFS({v},{b},"<="&{o},{y},{yr},{s},"PL")'.format(v=CT(c), b=CT("B"), o=ord_of[p], y=CT("A"), yr='"%d-*"' % p[0], s=CT("E")) for c in owner_cols) + ")", fmt=NUM)
        rr += 1
        if nci_line:
            put(ws, rr, 1, "Non-controlling interests (IFRS 10: the minority's share of net assets)")
            for j, p in enumerate(spine, 2):
                put(ws, rr, j, '=SUMIFS({v},{b},"<="&{o},{s},"BS",{e},0)'.format(v=CT("P"), b=CT("B"), o=ord_of[p], s=CT("E"), e="Chart_is_equity_placeholder"), fmt=NUM)
            rr += 1
        put(ws, rr, 1, "Total equity", F_BOLD)
        for j in range(2, len(spine) + 2):
            put(ws, rr, j, "=SUM(%s%d:%s%d)" % (L(j), na + 1, L(j), rr - 1), F_BOLD, NUM)
        te = rr; rr += 1
        put(ws, rr, 1, "check: net assets - total equity (must be 0)")
        for j in range(2, len(spine) + 2):
            put(ws, rr, j, "=ROUND(%s%d-%s%d,2)" % (L(j), na, L(j), te), fmt=NUM); ws.cell(row=rr, column=j).fill = FILL_CHECK
        return rr

    row_hdr = 0
    end1 = pnl_block(4, "Profit and loss, tool view (group share)", "M")
    end2 = bs_block(end1 + 2, "Balance sheet at period end, tool view (group share)", "M")
    end3 = pnl_block(end2 + 2, "Profit and loss, IFRS 10 view (100%, then attributed)", "R")
    put(ws, end3 + 1, 1, "  of which attributable to non-controlling interests")
    for j, p in enumerate(spine, 2):
        put(ws, end3 + 1, j, '=-SUMIFS(%s,%s,%s$%d,%s,"PL")' % (CT("P"), CT("A"), L(j), row_hdr, CT("E")), fmt=NUM)
    put(ws, end3 + 1, len(spine) + 2, "=SUM(%s%d:%s%d)" % (L(fy_cols[0]), end3 + 1, L(fy_cols[-1]), end3 + 1), fmt=NUM)
    put(ws, end3 + 2, 1, "  of which attributable to the owners of the parent", F_BOLD)
    for j in range(2, len(spine) + 3):
        put(ws, end3 + 2, j, "=%s%d-%s%d" % (L(j), end3, L(j), end3 + 1), F_BOLD, NUM)
    put(ws, end3 + 3, 1, "  reconciliation: owners' result - tool result = the NCI legs of P&L pairs the tool books to equity account 3700 (decision 12)")
    for j in range(2, len(spine) + 3):
        put(ws, end3 + 3, j, "=ROUND(%s%d-%s%d,2)" % (L(j), end3 + 2, L(j), end1), fmt=NUM)
    put(ws, end3 + 4, 1, "  check: that difference equals the reclassified P&L legs (must be 0)")
    for j, p in enumerate(spine, 2):
        put(ws, end3 + 4, j, '=ROUND(%s%d+SUMIFS(%s,%s,%s$%d,%s,"PL"),2)' % (L(j), end3 + 3, CT("Q"), CT("A"), L(j), row_hdr, CT("E")), fmt=NUM); ws.cell(row=end3 + 4, column=j).fill = FILL_CHECK
    put(ws, end3 + 4, len(spine) + 2, '=ROUND(%s%d+SUMIFS(%s,%s,"2024-*",%s,"PL"),2)' % (L(len(spine) + 2), end3 + 3, CT("Q"), CT("A"), CT("E")), fmt=NUM)
    ws.cell(row=end3 + 4, column=len(spine) + 2).fill = FILL_CHECK
    end4 = bs_block(end3 + 6, "Balance sheet at period end, IFRS 10 view (100% with an NCI line)", "R", nci_line=True, owner_cols=["M", "Q"])
    # the NCI line: the minority's share of the net assets (assets and liabilities rows), cumulative = 30% of ABSE's net assets at the closing rate
    for rr in range(end3 + 7, end4 + 1):
        if ws.cell(row=rr, column=1).value and str(ws.cell(row=rr, column=1).value).startswith("Non-controlling"):
            for j, p in enumerate(spine, 2):
                ws.cell(row=rr, column=j).value = '=SUMIFS({v},{b},"<="&{o},{c},"1*")+SUMIFS({v},{b},"<="&{o},{c},"2*")'.format(v=CT("P"), b=CT("B"), o=ord_of[p], c=CT("C"))
    note = ("Reading the IFRS view: assets and liabilities are the tool's figures plus the minority's share of ABSE's balances (Rows!Z, konsolidat#204); the NCI legs of the "
            "intercompany eliminations move from account 3700 to ABSE's own eliminated accounts (under IFRS 10 the pair is eliminated at 100%); the NCI line is 30% of ABSE's "
            "net assets at the closing rate. Owners' share capital and reserves equal the tool's; the owners' result differs from the tool's by the P&L legs the tool books to "
            "equity (decision 12), shown on the reconciliation line of the IFRS P&L.")
    put(ws, end4 + 2, 1, note).alignment = WRAP; ws.merge_cells(start_row=end4 + 2, start_column=1, end_row=end4 + 2, end_column=10); ws.row_dimensions[end4 + 2].height = 45
    stmt_rows = {"pnl_tool_result": end1, "bs_tool_check": end2, "pnl_ifrs_result": end3, "bs_ifrs_check": end4}

    # ------------------------------------------------------------------ Walkthrough
    ws = wb.create_sheet("Walkthrough", 1)
    ws.column_dimensions["A"].width = 10; ws.column_dimensions["B"].width = 70; ws.column_dimensions["C"].width = 18; ws.column_dimensions["D"].width = 60
    put(ws, 1, 1, "The year in nine steps: what to say, and the number to point at", F_TITLE)
    head(ws, 3, ["step", "talk track", "figure (EUR)", "where it comes from"], None)
    ws.freeze_panes = None
    st = row_hdr  # tool P&L header row
    def stmt(row, p):
        return "=Statements!%s%d" % (L(spine.index(p) + 2), row)
    steps = [
        ("1 Jan 2024", "We start from the FY2023 year-end trial balances of ten consolidated companies and one associate, in five currencies. The holding's investments in its subsidiaries are eliminated against their share capital by the opening consolidation journal; the balance sheet balances with the translation difference (CTA) in equity.",
         stmt(end2 - 1, (2023, 13)), "Statements: total equity at 2023-13 (after the year-end close moved the FY2023 result to retained earnings)"),
        ("FY2023 result", "The FY2023 result sits in the P&L accounts of the P12 file; the warehouse closes it to retained earnings in the Closing period (2023-13), translated at the 2023 annual average rate declared on FY2023 P12.",
         stmt(end1, (2023, 12)), "Statements: net result 2023-12"),
        ("P1-P5", "Each month: balances at the month's closing rate, movements of the P&L at the month's average rate, share capital at historical rates. Intercompany receivables equal payables after translation to the cent, so the eliminations leave nothing in the difference account.",
         "=ConsolTB!%s" % "M%d" % (ct_first + ord_of[(2024, 5)] * 0), "ConsolTB / IC: every pair matched (IC!W)"),
        ("P6: acquisition", "ABCZ acquired for EUR 11.0m. Goodwill = consideration - (net assets at book + fair value step-up), at the June closing rate. The 31 May balance sheet enters through the journal; ABCZ's own June movements through the entity layer. Costs expensed.",
         "=" + acq_gw_cell, "Acquisition: goodwill line"),
        ("P7-P11", "ABCZ consolidated like everyone else; management fees to ABCZ start; its balances now retranslate to each month's closing rate with the difference in CTA.",
         "=CTA!%s%d" % (L(ord_of[(2024, 9)] + 1), 2 + cons_ents.index("ABCZ")), "CTA: ABCZ 2024-9"),
        ("P12: disposal", "ABDK sold for EUR 7.0m on 31 December. Its net assets leave at the December closing rate, its accumulated CTA is recycled through the result, the proceeds land on the settlement account: gain on disposal.",
         "=" + dsp_gain_cell, "Disposal: gain (credit positive)"),
        ("FY2024 P&L", "Twelve months at monthly average rates, ABCZ from June, ABDK for the whole year (IFRS 10.B98: the results to the date of disposal stay in the group).",
         "=Statements!%s%d" % (L(len(spine) + 2), end1), "Statements: FY2024 net result (tool view)"),
        ("31 Dec 2024", "The consolidated balance sheet: goodwill on ABCZ, no ABDK, CTA in equity, the result of the year still open until the FY2024 close.",
         stmt(end2 - 1, (2024, 12)), "Statements: total equity 2024-12"),
        ("Go back", "Every period's movements are kept. Period 6 or 7 is read the same way as period 12: in this workbook by column, in konsol with =K.EPM(\"AQBIKE\", 2024, 7, account, \"consolidated_amount\", \"consolidated\") (sheet LiveCheck).",
         stmt(end1, (2024, 7)), "Statements: net result 2024-7"),
    ]
    for i, (step, talk, fig, src) in enumerate(steps, 4):
        put(ws, i, 1, step, F_BOLD); c = put(ws, i, 2, talk); c.alignment = WRAP; ws.row_dimensions[i].height = 60
        put(ws, i, 3, fig, F_LINK, NUM); put(ws, i, 4, src).alignment = WRAP
    # a cleaner P1-P5 figure: the intercompany difference account balance at 2024-5 (must be ~0)
    ws.cell(row=6, column=3).value = '=SUMIFS(%s,%s,"2024-5",%s,"%s")' % (CT("M"), CT("A"), CT("C"), d["policy"]["ic_difference_account"])
    ws.cell(row=6, column=4).value = "ConsolTB: intercompany difference account 6750 in 2024-5 (nothing: every pair matched)"
    k = len(steps) + 5
    put(ws, k, 1, "Checks", F_H2)
    checks = [("Every layer of every period nets to zero", "=ConsolTB!M%d" % ct_check_rows[0]),
              ("Largest difference between these formulas and the Python replica", "=ConsolTB!O%d" % ct_check_rows[1]),
              ("Tool balance sheet balances in every period (sum of the check row)", "=SUM(Statements!B%d:%s%d)" % (stmt_rows["bs_tool_check"], L(len(spine) + 1), stmt_rows["bs_tool_check"])),
              ("IFRS balance sheet balances in every period", "=SUM(Statements!B%d:%s%d)" % (stmt_rows["bs_ifrs_check"], L(len(spine) + 1), stmt_rows["bs_ifrs_check"]))]
    for i, (what, f) in enumerate(checks, k + 1):
        put(ws, i, 2, what); c = put(ws, i, 3, f, F_BOLD, NUM); c.fill = FILL_CHECK

    # ------------------------------------------------------------------ LiveCheck
    ws = wb.create_sheet("LiveCheck")
    ws.column_dimensions["A"].width = 10; ws.column_dimensions["B"].width = 44; ws.column_dimensions["C"].width = 18; ws.column_dimensions["D"].width = 80
    put(ws, 1, 1, "Read the same figures from konsol live with the Excel add-in", F_TITLE)
    put(ws, 2, 1, "The formulas below are stored as text so this file opens cleanly without the add-in. In a signed-in Excel, remove the leading apostrophe (or re-type =) and the cell reads the warehouse's consolidated movement for the group, period and account. Compare with column C.").alignment = WRAP
    ws.merge_cells("A2:D2"); ws.row_dimensions[2].height = 45
    head(ws, 4, ["period", "account", "this workbook (tool view)", "live formula (K.EPM, consolidated dataset)"], None)
    ws.freeze_panes = None
    rr = 5
    for p in ((2024, 6), (2024, 7), (2024, 12)):
        for a in ("4110", "4120", "1121", "6730", "CTA", "3700"):
            put(ws, rr, 1, pl(p)); put(ws, rr, 2, "%s %s" % (a, d["chart"].get(a, {}).get("name", "")))
            put(ws, rr, 3, '=SUMIFS(%s,%s,"%s",%s,"%s")' % (CT("M"), CT("A"), pl(p), CT("C"), a), F_LINK, NUM)
            put(ws, rr, 4, '=K.EPM("%s", %d, %d, "%s", "consolidated_amount", "consolidated")' % (d["group"], p[0], p[1], a))
            ws.cell(row=rr, column=4).data_type = "s"   # keep as text
            rr += 1
    put(ws, rr + 1, 1, "A balance-sheet balance is the sum of the movements from 2023-12 to the period (K.EPM returns movements; add the periods, or read the Rows sheet's logic).").alignment = WRAP
    ws.merge_cells(start_row=rr + 1, start_column=1, end_row=rr + 1, end_column=4)

    wb.save(OUT)
    print("wrote %s  (TB %d rows, Rows %d, IC %d, ConsolTB %d)" % (os.path.relpath(OUT, HERE), n_tb - 1, n_rows - 1, n_ic - 1, ct_last - ct_first + 1))


if __name__ == "__main__":
    build()
