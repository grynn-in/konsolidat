#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = ["openpyxl>=3.1"]
# ///
"""Build Aquila_Bike_Walkthrough.xlsx: the Aquila Bike consolidation done offline in Excel, with live
formulas, following the warehouse's rules step by step (movements -> ownership window -> translation ->
CTA -> intercompany -> deal journals -> equity method -> NCI attribution -> topside -> consolidated TB -> statements), so a
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
from collections import defaultdict

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
JV_ENTITY = "ABJV"


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
    check_cells = []      # (label, sheet, cell): every one must read 0 after recalculation
    py_checks = {}        # label -> the same check computed in Python from the replica and expected.json
    figures = {}

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
        ("1 Jan 2024: nine consolidated entities (ABCZ joins in June, ABDK leaves at the year end), one 30% associate (ABPT) and, from FY2024 P1, one joint "
         "venture (ABJV, equity method); the FY2023 year-end trial balances are the opening position. The holding's investments are eliminated "
         "against the subsidiaries' share capital by the opening journal, which also opens the minority of ABSE (sheet Topside).", F_BODY),
        ("FY2024 P1-P5: monthly closes. Balance sheets at each month's closing rate, P&L at each month's average rate, share capital at "
         "historical rates, the difference in CTA. Intercompany pairs eliminated in full on the declared account pairs with the partner on both sides. "
         "ABSE is carried at 100%; each month a journal attributes the minority's 30% of its result and CTA to the NCI line (sheet NCI attribution). "
         "ABJV, held 30% by ABDE and 30% by ABFR, is picked up at 60% by the equity method on the group's declaration (sheet Joint venture ABJV).", F_BODY),
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
        ("1. A deal must be dated on the first day of a period (konsolidat#278) and its acquired balance sheet is the last period-end before "
         "the acquisition period (konsol#406). The example does both.", F_BODY),
        ("2. The acquired entity's opening balance sheet is frozen at the acquisition-period closing rate (never retranslated); the goodwill "
         "likewise. Its own movements from the acquisition period on are retranslated normally.", F_BODY),
        ("3. The parent's own books record deal cash through the group's Deal Settlement Account (1235) and keep the investment at cost; "
         "the acquisition journal credits the investment, the disposal journal debits the proceeds. No template eliminates a parent's own "
         "gain on disposal, so the example's parent books none.", F_BODY),
        ("4. The equity-method entry (associate ABPT, joint venture ABJV) is shown as it must be: share of result at the average rate, debit investment / credit "
         "income. The warehouse model posted both legs with one sign and untranslated when this was written (konsolidat issue filed 7 Nov 2026; fixed on branch fix-equity-method-journal).", F_BODY),
        ("5. An entity the group reaches along two ownership paths (ABJV: 30% through ABDE and 30% through ABFR) needs the group's declared method "
         "when the paths add past 50% and no path is all-full (IFRS 10.B35 presumption of control). The percentage decides nothing; only the group can say "
         "whether 60% is control or joint control. Until it is declared the build names the group and the entity (assert_method_declared_for_multi_path) "
         "and the method resolves to none: nothing consolidates, nothing is picked up.", F_BODY),
        ("6. Profit and loss posted by the journal layers (the equity-method pickup, the deal journals) is not closed to retained earnings at the year end "
         "(konsolidat#316). The FY2023 pickup of ABPT therefore stays in the P&L accounts after 2023-13, and the Statements sheet carries it on the line "
         "'Result not yet closed'. An associate's pickup excludes the year-end close rows, so ABPT has no pickup in the Closing period.", F_BODY),
        ("", F_BODY),
        ("Sheets", F_H2),
    ]
    guide = [
        ("Walkthrough", "the story with the key figures linked to the sheets below"),
        ("Entities, Chart, Periods, Rates", "master data: entities and ownership, the group chart with each account's translation rule, the calendar, governed Closing/Average rates and the historical equity rates"),
        ("TB", "every trial-balance line as uploaded (period-end balances, local currency, debit +, credit -), one row per entity, period, account and partner"),
        ("Rows", "the warehouse's consolidated trial-balance rows: movement from the balances (first file = the balance, year-end close synthesised in 2023-13), ownership window, rate, retranslation of balance-sheet balances to each closing rate, the close translation, group amount (100%) and the minority's share"),
        ("CTA", "the translation difference per entity and period: minus the sum of the entity's group amounts"),
        ("IC", "intercompany pairs matched on translated amounts (balances cumulative, P&L by period), matched / residual, and the elimination legs, in full (no NCI leg)"),
        ("Acquisition, Disposal", "the two deal journals line by line"),
        ("EquityMethod, Topside", "the equity-method share of result (associate ABPT, joint venture ABJV); the opening journal CJ-OPEN-2023, read from expected.json"),
        ("NCI attribution", "the per-period journal that moves the minority's 30% of ABSE's result and CTA to the NCI line (3700), and the NCI roll-forward"),
        ("Joint venture ABJV", "two links of 30%, the sum of 60%, why that is not control, the declaration, the pickup per period and the holders' cost"),
        ("ConsolTB", "the fully consolidated trial balance per period and layer, with the Python replica as a cross-check column (must be 0)"),
        ("Statements", "P&L per period and FY, balance sheet per period end: the IFRS 10 presentation the tool produces (100% line by line, NCI line 3700), and the note on how NCI is computed"),
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
    head(ws, 1, ["code", "name", "currency", "ownership %", "method", "owned since", "owned until", "consolidated?", "carried at (layer 1)", "held by"],
         [8, 34, 9, 11, 10, 12, 12, 13, 14, 26],
         {"owned until": "Blank in konsol means still owned; here 9999-12-31. ABDK: the disposal date.",
          "consolidated?": "full or proportional: line by line. equity: one-line share of result. none: excluded.",
          "ownership %": "The effective ownership: the sum over the paths of the product of the link percentages (ABJV: 30% through ABDE + 30% through ABFR = 60%).",
          "carried at (layer 1)": "A controlled subsidiary is carried at 100% in layer 1 (konsolidat#204 option (a)); the minority is the NCI line, posted by the attribution journal.",
          "method": "ABJV: declared by AQBIKE (sheet Joint venture ABJV); two paths that add past 50% and no all-full path need a declaration."})
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
        put(ws, i, 9, '=IF(H%d="yes",1,0)' % i, fmt="0%")
        holders = ["%s %d%%" % (l["owner"], l["pct"]) for l in d["ownership_links"] if l["entity"] == code and l["owner"]]
        put(ws, i, 10, " + ".join(holders) if holders else "%s %d%%" % (d["group"], e["own"]), F_INPUT)
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
            "retranslation", "close adj P&L", "close adj RE", "translated", "carried at", "group amount", "nci amount", "key", "is_bs", "is_equity", "is_pnl", "retranslated key", "year"]
    head(ws, 1, cols, [7, 8, 6, 7, 7, 10, 9, 14, 14, 14, 6, 14, 7, 9, 9, 10, 10, 10, 14, 13, 13, 13, 14, 6, 14, 14, 26, 5, 6, 6, 6, 6],
         {"kind": "activity: a movement between two uploaded balances (the first upload is the whole balance). close_pnl / close_re: the year-end close the warehouse synthesises in period 13 of a Period-end-balance year: each P&L account is reversed and the year's result moves to retained earnings. filler: a balance-sheet key with no movement this period, carried so its balance is restated to the new closing rate.",
          "in window": "1 when the period's first day is inside the entity's ownership window (Entities!F:G) and the entity consolidates line by line. 0 rows are dropped by the warehouse: shown here, amounts in scope are 0.",
          "rate": "closing (balance sheet), average (P&L), historical (share capital / premium, once the period is on or after the rate date), 1 for EUR. A Closing period uses its year's last Regular period's rates.",
          "retranslation": "konsolidat#257: cumulative local balance before this period x (this closing rate - previous closing rate), on balance-sheet, non-equity, closing-rate keys. Equity is never revalued.",
          "close adj P&L": "konsolidat#259: on a close row the reversal returns the key's translated year to zero: sum(local before) x rate - sum(translated before).",
          "close adj RE": "konsolidat#259: retained earnings takes the year's TRANSLATED result, so the close period has no CTA.",
          "translated": "local x rate + retranslation + close adjustments (100%).",
          "group amount": "= translated (100%): a controlled subsidiary is carried in full (konsolidat#204 option (a)).",
          "nci amount": "translated x (1 - ownership %): the minority's share of the row. It is not a layer; the attribution journal posts the P&L and CTA part of it to 3700 (sheet NCI attribution)."})
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
        put(ws, i, 26, "=W%d*(1-INDEX(%s,MATCH(A%d,%s,0)))*K%d" % (i, ent_col("D"), i, ENT, i), fmt=NUM)
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
               "local a", "local b", "translated a", "translated b", "matched", "residual a", "residual b", "difference", "cause", "status",
               "m_a", "d_a", "d_b", "post m_a", "post d_a", "post d_b", "to account a", "to account b", "to difference account"]
    head(ws, 1, ic_cols, [8, 6, 7, 8, 7, 8, 9, 7, 14] + [12] * 10 + [11] * 9,
         {"basis": "balance: a balance-sheet pair compares cumulative translated amounts to date; movement: a P&L pair compares the period.",
          "event": "joined: the first period both sides are in the group; left: the period after one side left (everything eliminated is reversed).",
          "translated a": "Both sides are carried at 100% (konsolidat#204 option (a)), so the translated amount is the group amount and an intercompany pair with a partly owned subsidiary is eliminated in full: no NCI leg, no share columns.",
          "matched": "the offsetting amount both sides agree on, in full: min(|a|,|b|) when the signs differ.",
          "cause": "none: within half a cent. fx: the currencies differ, or the local amounts agree. booking: the local amounts disagree.",
          "m_a": "the matched amount eliminated on account a (account b takes the opposite sign). d_a / d_b: each side's residual, to the difference account.",
          "post m_a": "what this period posts: for a balance pair the change against the previous row of the pair; a movement pair posts the period's figure. Half a cent or less posts nothing.",
          "to account a": "the elimination legs by account: account a gets post m_a + post d_a; account b gets -post m_a + post d_b; the difference account gets -(post d_a + post d_b)."})
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
        put(ws, i, 12, side("W", "C%d" % i, "D%d" % i, "E%d" % i), fmt=NUM)
        put(ws, i, 13, side("W", "E%d" % i, "F%d" % i, "C%d" % i), fmt=NUM)
        put(ws, i, 14, "=IF(L%d*M%d<0,MIN(ABS(L%d),ABS(M%d)),0)" % (i, i, i, i), fmt=NUM)
        put(ws, i, 15, "=L%d-SIGN(L%d)*N%d" % (i, i, i), fmt=NUM); put(ws, i, 16, "=M%d-SIGN(M%d)*N%d" % (i, i, i), fmt=NUM)
        put(ws, i, 17, "=L%d+M%d" % (i, i), fmt=NUM)
        cur_a = 'INDEX(%s,MATCH(C%d,%s,0))' % (ent_col("C"), i, ENT); cur_b = 'INDEX(%s,MATCH(E%d,%s,0))' % (ent_col("C"), i, ENT)
        put(ws, i, 18, '=IF(ABS(Q{r})<0.005,"none",IF({ca}<>{cb},"fx",IF(ABS(J{r}+K{r})>=0.005,"booking","fx")))'.format(r=i, ca=cur_a, cb=cur_b))
        put(ws, i, 19, '=IF(R{r}="none","matched",IF(AND(R{r}="fx",NOT(AND(G{r}="balance",{ca}<>{cb}))),"fx_difference",IF(ABS(Q{r})<={tol},"within_tolerance","over_tolerance")))'.format(r=i, ca=cur_a, cb=cur_b, tol=tol))
        put(ws, i, 20, "=-SIGN(L%d)*N%d" % (i, i), fmt=NUM)
        put(ws, i, 21, "=-O%d" % i, fmt=NUM); put(ws, i, 22, "=-P%d" % i, fmt=NUM)
        prev_same = '(ROW()>2)*(I%d=I%d)' % (i, i - 1) if i > 2 else "0"
        for k, (col, src) in enumerate((("W", "T"), ("X", "U"), ("Y", "V"))):
            prev_ref = "%s%d" % (src, i - 1) if i > 2 else "0"
            f = '=IF(ABS({s}{r}-IF(AND($G{r}="balance",{same}),{prev},0))<0.005,0,{s}{r}-IF(AND($G{r}="balance",{same}),{prev},0))'.format(
                s=src, r=i, same=prev_same if i > 2 else "FALSE", prev=prev_ref)
            put(ws, i, 23 + k, f, fmt=NUM)
        put(ws, i, 26, "=W%d+X%d" % (i, i), fmt=NUM); put(ws, i, 27, "=-W%d+Y%d" % (i, i), fmt=NUM)
        put(ws, i, 28, "=-(X%d+Y%d)" % (i, i), fmt=NUM)
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
    head(ws, 1, ["period", "investee", "share", "currency", "result (local, Dr +)", "average rate", "EQ_INCOME (EUR)", "EQ_INVEST (EUR)", "method source"], [9, 10, 7, 9, 18, 12, 16, 16, 14],
         {"result (local, Dr +)": "The investee's P&L movements of the period (gold_trial_balance), without the synthesised year-end close rows (konsolidat#279): an associate's pickup excludes close rows, so there is none in the Closing period 2023-13.",
          "share": "The effective ownership: ABPT 30%; ABJV 30% through ABDE + 30% through ABFR = 60%.",
          "method source": "link: the links settle the method. declared: the group's declaration decides (ABJV).",
          "EQ_INCOME (EUR)": "share of result x average rate (a profit is a credit, negative). EQ_INVEST is the debit counterpart. Entries at or below 0.01 are not posted."})
    investees = [e for e in ent_codes if any(o.resolve(e, p)["method"] == "equity" for p in o.mov[e])]
    r = 2
    for e in investees:
        for p in sorted(o.mov[e]):
            if o.resolve(e, p)["method"] != "equity" or p[1] == 13:
                continue
            put(ws, r, 1, pl(p)); put(ws, r, 2, e); put(ws, r, 3, "=INDEX(%s,MATCH(B%d,%s,0))" % (ent_col("D"), r, ENT), fmt="0%")
            put(ws, r, 4, "=INDEX(%s,MATCH(B%d,%s,0))" % (ent_col("C"), r, ENT))
            put(ws, r, 5, '=SUMIFS(%s,%s,B%d,%s,A%d,%s,1,%s,"activity")' % (RW("J"), RW("A"), r, RW("B"), r, RW("AD"), RW("F")), fmt=NUM)
            put(ws, r, 6, "=" + rate_formula("Average", "D%d" % r, 'INDEX(%s,MATCH(A%d,%s,0))' % (per_col("G"), r, PER)), fmt=RATE)
            put(ws, r, 7, "=IF(ABS(E%d*C%d*F%d)<=0.01,0,E%d*C%d*F%d)" % (r, r, r, r, r, r), fmt=NUM); put(ws, r, 8, "=-G%d" % r, fmt=NUM)
            put(ws, r, 9, o.resolve(e, p)["source"])
            r += 1
    n_eq = r - 1
    EQ = lambda c: "EquityMethod!$%s$2:$%s$%d" % (c, c, max(n_eq, 2))

    # ------------------------------------------------------------------ NCI attribution
    ws = wb.create_sheet("NCI attribution")
    nci_acct = d["policy"]["nci_account"]
    re_acct = "3300"
    ws.column_dimensions["A"].width = 26
    for j in range(2, 18):
        ws.column_dimensions[L(j)].width = 15
    put(ws, 1, 1, "NCI attribution: the minority's share of ABSE's result and CTA, one journal per period (konsolidat#204 option (a))", F_TITLE)
    notes_nci = [
        "ABSE is carried at 100%% line by line. The minority (30%%) is one line, account %s, and it is fed by two things only." % nci_acct,
        "1. The opening NCI: the opening consolidation journal CJ-OPEN-2023 credits %s with 30%% of ABSE's equity (share capital and premium at the historical rate; the legal reserve and the opening retained earnings 3300 at the FY2023 P12 closing rate) (sheet Topside; for an acquired subsidiary the acquisition journal does it)." % nci_acct,
        "2. A per-period journal NCI-<group>-<entity>-<year>-P<n>: Dr retained earnings %s for the minority's share of the period's result (30%% x the translated P&L accounts, without close rows); Dr CTA for 30%% of the entity's CTA movement; Cr %s for the sum. It nets to zero." % (re_acct, nci_acct),
        "So the closing NCI is the opening NCI plus the attributions, and it equals the minority's share of ABSE's net assets at the closing rate (the check below). A dividend would reduce it; this example pays none.",
    ]
    for k, t in enumerate(notes_nci, 2):
        c = put(ws, k, 1, t); c.alignment = WRAP
        ws.merge_cells(start_row=k, start_column=1, end_row=k, end_column=12); ws.row_dimensions[k].height = 30
    h0 = len(notes_nci) + 3
    head(ws, h0, ["journal", "period", "ordinal", "entity", "minority %", "result, translated (Dr +)", "minority's share of result", "entity CTA movement (Dr +)", "minority's share of CTA",
                  "Dr %s retained earnings" % re_acct, "Dr CTA", "Cr %s NCI (negative)" % nci_acct, "nets to zero", "expected.json %s" % re_acct, "expected.json CTA", "expected.json %s" % nci_acct, "diff (must be 0)"],
         None, {"result, translated (Dr +)": "Sum of Rows!W over the entity's P&L accounts for the period, activity rows only (no year-end close rows). A profit is negative (credit).",
                "entity CTA movement (Dr +)": "Sheet CTA: minus the sum of the entity's group amounts for the period.",
                "Cr %s NCI (negative)" % nci_acct: "Dr + convention: the credit is negative. = share of result + share of CTA."})
    ws.freeze_panes = None
    jr = sorted({(x["journal"], x["entity"], x["period"]) for x in exp["nci_attribution"]}, key=lambda t: (ord_of[tuple(int(v) for v in t[2].split("-"))], t[1]))
    exp_nci = {}
    for x in exp["nci_attribution"]:
        exp_nci[(x["journal"], x["role"])] = x["amount"]
    cta_rng = "CTA!$B$2:$%s$%d" % (L(len(spine) + 1), n_cta)
    nci_first = h0 + 1
    for i, (jid, e, pstr) in enumerate(jr, nci_first):
        put(ws, i, 1, jid); put(ws, i, 2, pstr); put(ws, i, 3, '=INDEX(%s,MATCH(B%d,%s,0))' % (per_col("D"), i, PER)); put(ws, i, 4, e)
        put(ws, i, 5, "=1-INDEX(%s,MATCH(D%d,%s,0))" % (ent_col("D"), i, ENT), fmt="0%")
        put(ws, i, 6, '=SUMIFS(%s,%s,D%d,%s,B%d,%s,1,%s,"activity")' % (RW("W"), RW("A"), i, RW("B"), i, RW("AD"), RW("F")), fmt=NUM)
        put(ws, i, 7, "=F%d*E%d" % (i, i), fmt=NUM)
        put(ws, i, 8, "=INDEX(%s,MATCH(D%d,CTA!$A$2:$A$%d,0),MATCH(B%d,CTA!$B$1:$%s$1,0))" % (cta_rng, i, n_cta, i, L(len(spine) + 1)), fmt=NUM)
        put(ws, i, 9, "=H%d*E%d" % (i, i), fmt=NUM)
        put(ws, i, 10, "=-G%d" % i, fmt=NUM); put(ws, i, 11, "=-I%d" % i, fmt=NUM); put(ws, i, 12, "=G%d+I%d" % (i, i), fmt=NUM)
        put(ws, i, 13, "=ROUND(J%d+K%d+L%d,6)" % (i, i, i), fmt=NUM)
        put(ws, i, 14, exp_nci.get((jid, "retained_earnings"), 0.0), F_INPUT, NUM); put(ws, i, 15, exp_nci.get((jid, "cta"), 0.0), F_INPUT, NUM); put(ws, i, 16, exp_nci.get((jid, "nci"), 0.0), F_INPUT, NUM)
        put(ws, i, 17, "=ROUND(MAX(ABS(J%d-N%d),ABS(K%d-O%d),ABS(L%d-P%d)),2)" % (i, i, i, i, i, i), fmt=NUM)
        ws.cell(row=i, column=17).fill = FILL_CHECK
    nci_last = nci_first + len(jr) - 1
    NA = lambda c: "'NCI attribution'!$%s$%d:$%s$%d" % (c, nci_first, c, nci_last)
    r = nci_last + 2
    put(ws, r, 1, "checks", F_BOLD)
    put(ws, r + 1, 1, "every journal nets to zero"); put(ws, r + 1, 13, "=MAX(MAX(M%d:M%d),-MIN(M%d:M%d))" % (nci_first, nci_last, nci_first, nci_last), fmt=NUM); ws.cell(row=r + 1, column=13).fill = FILL_CHECK
    check_cells.append(("nci_journals_net_to_zero", "NCI attribution", "M%d" % (r + 1)))
    put(ws, r + 2, 1, "largest difference to expected.json"); put(ws, r + 2, 17, "=MAX(Q%d:Q%d)" % (nci_first, nci_last), fmt=NUM); ws.cell(row=r + 2, column=17).fill = FILL_CHECK
    check_cells.append(("nci_vs_expected_json", "NCI attribution", "Q%d" % (r + 2)))
    r += 4
    put(ws, r, 1, "NCI roll-forward for %s, EUR (credit shown positive)" % NCI_ENTITY, F_H2)
    close_ord = ord_of[(2024, 12)]
    roll = [("Opening NCI: Cr %s in the opening journal CJ-OPEN-2023" % nci_acct, '=-SUMIFS(Topside!$G$2:$G$%d,Topside!$C$2:$C$%d,"%s",Topside!$D$2:$D$%d,"%s")' % (len(exp["topside"]) + 1, len(exp["topside"]) + 1, NCI_ENTITY, len(exp["topside"]) + 1, nci_acct)),
            ("Attributions, FY2023 P12 to FY2024 P12 (sum of the journals above)", "=-SUM(L%d:L%d)" % (nci_first, nci_last)),
            ("Closing NCI at 2024-12", "=B%d+B%d" % (r + 1, r + 2)),
            ("Minority %% x ABSE net assets at the 2024-12 closing rate (Rows: balance-sheet, non-equity, translated, to ordinal %d)" % close_ord,
             '=(1-INDEX(%s,MATCH("%s",%s,0)))*SUMIFS(%s,%s,"%s",%s,1,%s,0,%s,"<="&%d)' % (
                 ent_col("D"), NCI_ENTITY, ENT, RW("W"), RW("A"), NCI_ENTITY, RW("AB"), RW("AC"), RW("C"), close_ord)),
            ("check: closing NCI - minority's share of net assets (must be 0)", "=ROUND(B%d-B%d,2)" % (r + 3, r + 4))]
    for k, (what, f) in enumerate(roll, r + 1):
        put(ws, k, 1, what).alignment = WRAP; put(ws, k, 2, f, F_BOLD, NUM)
        ws.row_dimensions[k].height = 30
    ws.column_dimensions["A"].width = 60
    ws.cell(row=r + 5, column=2).fill = FILL_CHECK
    check_cells.append(("nci_closing_is_minority_share_of_net_assets", "NCI attribution", "B%d" % (r + 5)))
    nci_roll_cells = {"opening": "'NCI attribution'!$B$%d" % (r + 1), "attrib": "'NCI attribution'!$B$%d" % (r + 2), "closing": "'NCI attribution'!$B$%d" % (r + 3), "check": "'NCI attribution'!$B$%d" % (r + 5)}
    # the same figures in Python
    nci_open = -sum(x["amount"] for x in exp["topside"] if x["entity"] == NCI_ENTITY and x["account"] == nci_acct)
    nci_attr = -sum(x["amount"] for x in exp["nci_attribution"] if x["account"] == nci_acct)
    minority = 1 - d["entities"][NCI_ENTITY]["own"] / 100.0
    na_close = sum(rw["translated"] for rw in o.rows if rw["entity"] == NCI_ENTITY and o.is_bs(rw["account"]) and not o.is_equity(rw["account"])
                   and ord_of[rw["period"]] <= close_ord)
    py_checks["nci_closing_is_minority_share_of_net_assets"] = nci_open + nci_attr - minority * na_close
    figures.update({"nci_opening": nci_open, "nci_attributions": nci_attr, "nci_closing_2024_12": nci_open + nci_attr})

    # ------------------------------------------------------------------ Joint venture ABJV
    ws = wb.create_sheet("Joint venture ABJV")
    ws.column_dimensions["A"].width = 44
    for j in range(2, 9):
        ws.column_dimensions[L(j)].width = 18
    jv = JV_ENTITY
    put(ws, 1, 1, "Joint venture ABJV (Aquila Shared Mobility B.V.): 30% held by ABDE, 30% by ABFR, equity method on the group's declaration", F_TITLE)
    put(ws, 3, 1, "1. The two links (Ownership_Periods: owner_entity)", F_H2)
    for j, h in enumerate(["holder", "pct", "method on the link", "since"], 1):
        c = put(ws, 4, j, h, F_HEAD); c.fill = FILL_HEAD
    links = [l for l in d["ownership_links"] if l["entity"] == jv]
    for i, l in enumerate(links, 5):
        put(ws, i, 1, l["owner"], F_INPUT); put(ws, i, 2, l["pct"] / 100.0, F_INPUT, "0%"); put(ws, i, 3, l["method"], F_INPUT)
        put(ws, i, 4, dt.date.fromisoformat(l["since"]), F_INPUT, "yyyy-mm-dd")
    lk_end = 4 + len(links)
    put(ws, lk_end + 1, 1, "Effective ownership: the paths add", F_BOLD); put(ws, lk_end + 1, 2, "=SUM(B5:B%d)" % lk_end, F_BOLD, "0%")
    put(ws, lk_end + 2, 1, "check: equals Entities!ownership % (must be 0)"); put(ws, lk_end + 2, 2, "=ROUND(B%d-INDEX(%s,MATCH(\"%s\",%s,0)),6)" % (lk_end + 1, ent_col("D"), jv, ENT), fmt=NUM)
    ws.cell(row=lk_end + 2, column=2).fill = FILL_CHECK
    check_cells.append(("jv_links_sum_to_entities_ownership", "Joint venture ABJV", "B%d" % (lk_end + 2)))
    py_checks["jv_links_sum_to_entities_ownership"] = sum(l["pct"] for l in links) - d["entities"][jv]["own"]
    r = lk_end + 4
    put(ws, r, 1, "2. Why 60% does not give control", F_H2)
    why = ("Each holder has 30% and no path is all-full, so the links do not settle the method. 60% is past the 50% presumption of control (IFRS 10.B35), but the presumption "
           "is rebuttable and the stake is split across two group entities. The shareholders' agreement requires the consent of the parties sharing control for the relevant "
           "decisions, which is joint control (IFRS 11.7), not control. The percentage decides nothing; only the group can say, so the tool asks for a declaration.")
    c = put(ws, r + 1, 1, why); c.alignment = WRAP; ws.merge_cells(start_row=r + 1, start_column=1, end_row=r + 1, end_column=6); ws.row_dimensions[r + 1].height = 62
    r += 3
    put(ws, r, 1, "3. The declaration (Method_Declarations sheet of the master workbook)", F_H2)
    for j, h in enumerate(["group", "entity", "method", "from", "to", "reason"], 1):
        c = put(ws, r + 1, j, h, F_HEAD); c.fill = FILL_HEAD
    for i, x in enumerate([x for x in d["declarations"] if x["entity"] == jv], r + 2):
        put(ws, i, 1, x["group"], F_INPUT); put(ws, i, 2, x["entity"], F_INPUT); put(ws, i, 3, x["method"], F_INPUT)
        put(ws, i, 4, dt.date.fromisoformat(x["from"]), F_INPUT, "yyyy-mm-dd"); put(ws, i, 5, x["to"] or "open", F_INPUT); put(ws, i, 6, x["reason"], F_INPUT)
    r += 2 + len([x for x in d["declarations"] if x["entity"] == jv]) + 1
    put(ws, r, 1, "If the declaration is missing", F_BOLD)
    miss = ("The build fails assert_method_declared_for_multi_path naming the group (AQBIKE), the entity (ABJV), the period, the 60% and the two paths. "
            "Until it is declared the method resolves to none: nothing consolidates and nothing is picked up for ABJV (the replica's resolve() returns method none, source undeclared).")
    c = put(ws, r + 1, 1, miss); c.alignment = WRAP; ws.merge_cells(start_row=r + 1, start_column=1, end_row=r + 1, end_column=6); ws.row_dimensions[r + 1].height = 48
    nd = dict(d); nd["declarations"] = []
    und = Offline(nd).resolve(jv, (2024, 6))
    py_checks["jv_undeclared_resolves_to_none"] = 0.0 if (und["method"], und["source"]) == ("none", "undeclared") else 1.0
    r += 3
    put(ws, r, 1, "4. The group's pickup: 60% of ABJV's result (EUR, rate 1), from sheet EquityMethod", F_H2)
    for j, h in enumerate(["period", "ABJV result (local, Dr +)", "x 60%", "EQ_INCOME (sheet EquityMethod)", "expected.json EQ_INCOME", "diff (must be 0)"], 1):
        c = put(ws, r + 1, j, h, F_HEAD); c.fill = FILL_HEAD
        c.alignment = Alignment(wrap_text=True, vertical="center")
    ws.row_dimensions[r + 1].height = 30
    exp_jv = {x["period"]: x["amount"] for x in exp["equity_method"] if x["entity"] == jv and x["account"] == "EQ_INCOME"}
    jv_periods = [p for p in sorted(o.mov[jv]) if o.resolve(jv, p)["method"] == "equity" and p[1] != 13]
    jv_first = r + 2
    for i, p in enumerate(jv_periods, jv_first):
        put(ws, i, 1, pl(p))
        put(ws, i, 2, '=SUMIFS(%s,%s,"%s",%s,A%d)' % (EQ("E"), EQ("B"), jv, EQ("A"), i), fmt=NUM)
        put(ws, i, 3, '=B%d*INDEX(%s,MATCH("%s",%s,0))' % (i, ent_col("D"), jv, ENT), fmt=NUM)
        put(ws, i, 4, '=SUMIFS(%s,%s,"%s",%s,A%d)' % (EQ("G"), EQ("B"), jv, EQ("A"), i), fmt=NUM)
        put(ws, i, 5, exp_jv.get(pl(p), 0.0), F_INPUT, NUM)
        put(ws, i, 6, "=ROUND(D%d-E%d,2)" % (i, i), fmt=NUM); ws.cell(row=i, column=6).fill = FILL_CHECK
    jv_last = jv_first + len(jv_periods) - 1
    put(ws, jv_last + 1, 1, "FY2024", F_BOLD)
    for col in "BCDE":
        put(ws, jv_last + 1, "ABCDE".index(col) + 1, "=SUM(%s%d:%s%d)" % (col, jv_first, col, jv_last), F_BOLD, NUM)
    put(ws, jv_last + 1, 6, "=MAX(MAX(F%d:F%d),-MIN(F%d:F%d))" % (jv_first, jv_last, jv_first, jv_last), F_BOLD, NUM); ws.cell(row=jv_last + 1, column=6).fill = FILL_CHECK
    check_cells.append(("jv_pickup_vs_expected_json", "Joint venture ABJV", "F%d" % (jv_last + 1)))
    py_checks["jv_pickup_vs_expected_json"] = max([abs(sum(l["amount"] for l in o.eq_lines if l["entity"] == jv and l["account"] == "EQ_INCOME" and pl(l["period"]) == pl(p)) - exp_jv.get(pl(p), 0.0)) for p in jv_periods] + [0.0])
    figures["jv_pickup_fy2024"] = sum(exp_jv.values())
    r = jv_last + 3
    put(ws, r, 1, "5. The holders' cost: 1142 investments in associates, booked in FY2024 P1 (Dr 1142 / Cr 1241 cash)", F_H2)
    for j, h in enumerate(["holder", "1142 at 2024-1 (TB)", "1142 at 2023-12 (TB)", "cost", "30% x ABJV paid-in capital", "diff (must be 0)"], 1):
        c = put(ws, r + 1, j, h, F_HEAD); c.fill = FILL_HEAD
        c.alignment = Alignment(wrap_text=True, vertical="center")
    ws.row_dimensions[r + 1].height = 30
    paid = "-(SUMIFS(%s,%s,\"%s\",%s,\"2024-1\",%s,\"3100\")+SUMIFS(%s,%s,\"%s\",%s,\"2024-1\",%s,\"3200\"))" % (
        TBA, TBE, jv, TBP, "TB!$C$2:$C$%d" % n_tb, TBA, TBE, jv, TBP, "TB!$C$2:$C$%d" % n_tb)
    for i, l in enumerate(links, r + 2):
        h = l["owner"]
        put(ws, i, 1, h, F_INPUT)
        put(ws, i, 2, '=SUMIFS(%s,%s,A%d,%s,"2024-1",%s,"1142")' % (TBA, TBE, i, TBP, "TB!$C$2:$C$%d" % n_tb), fmt=NUM)
        put(ws, i, 3, '=SUMIFS(%s,%s,A%d,%s,"2023-12",%s,"1142")' % (TBA, TBE, i, TBP, "TB!$C$2:$C$%d" % n_tb), fmt=NUM)
        put(ws, i, 4, "=B%d-C%d" % (i, i), fmt=NUM)
        put(ws, i, 5, "=%s*%s" % (l["pct"] / 100.0, paid), fmt=NUM)
        put(ws, i, 6, "=ROUND(D%d-E%d,2)" % (i, i), fmt=NUM); ws.cell(row=i, column=6).fill = FILL_CHECK
        check_cells.append(("jv_holder_cost_%s" % h, "Joint venture ABJV", "F%d" % i))
        tbd = {(k[0], k[1], k[2], k[3]): k[5] for k in d["tb_cents"]}
        cost_py = (tbd.get((h, 2024, 1, "1142"), 0) - tbd.get((h, 2023, 12, "1142"), 0)) / 100.0
        paid_py = -(tbd.get((jv, 2024, 1, "3100"), 0) + tbd.get((jv, 2024, 1, "3200"), 0)) / 100.0
        py_checks["jv_holder_cost_%s" % h] = cost_py - l["pct"] / 100.0 * paid_py
    hold_end = r + 1 + len(links)
    put(ws, hold_end + 1, 1, "Cost of both stakes", F_BOLD); put(ws, hold_end + 1, 4, "=SUM(D%d:D%d)" % (r + 2, hold_end), F_BOLD, NUM)
    put(ws, hold_end + 2, 1, "plus the pickups to 2024-12 (EQ_INVEST)"); put(ws, hold_end + 2, 4, '=SUMIFS(%s,%s,"%s")' % (EQ("H"), EQ("B"), jv), fmt=NUM)
    put(ws, hold_end + 3, 1, "Carrying amount of ABJV in the group at 2024-12", F_BOLD); put(ws, hold_end + 3, 4, "=D%d+D%d" % (hold_end + 1, hold_end + 2), F_BOLD, NUM)
    c = put(ws, hold_end + 5, 1, "The group carries the stake as the holders' cost (1142 in their own books) plus the EQ_INVEST pickups; the pickup is not booked twice. Cash is the balancing line of every period after the first on each holder, so their P&L does not move.")
    c.alignment = WRAP; ws.merge_cells(start_row=hold_end + 5, start_column=1, end_row=hold_end + 5, end_column=6); ws.row_dimensions[hold_end + 5].height = 34

    # ------------------------------------------------------------------ Topside
    ws = wb.create_sheet("Topside")
    head(ws, 1, ["journal", "period", "entity", "account", "debit (EUR)", "credit (EUR)", "amount (Dr +)", "description", "diff to inputs.json (must be 0)"], [14, 9, 8, 9, 14, 14, 14, 60, 16],
         {"journal": "Consolidation Journal CJ-OPEN-2023 (Consolidation_Journals / CJ_Lines in the master workbook), approved: the first consolidation's elimination of the parent's investments in its founded subsidiaries against their share capital and premium at the historical rate, and the opening NCI of ABSE (30% of its equity: share capital and premium at the historical rate, the legal reserve and the opening retained earnings 3300 at the FY2023 P12 closing rate; Cr 3700, with the minority's share of retained earnings Dr 3300).",
          "amount (Dr +)": "Read from expected.json topside: the replica's rows of the opening journal.",
          "diff to inputs.json (must be 0)": "The same line in inputs.json opening_journal (debit - credit)."})
    desc = {(l["data_area_id"], l["main_account"]): l["description"] for l in d["opening_journal"]}
    inp = {(l["data_area_id"], l["main_account"]): float(l["debit_amount"] or 0) - float(l["credit_amount"] or 0) for l in d["opening_journal"]}
    top_rows = exp["topside"]
    for i, x in enumerate(top_rows, 2):
        put(ws, i, 1, x["journal"]); put(ws, i, 2, x["period"]); put(ws, i, 3, x["entity"]); put(ws, i, 4, x["account"])
        put(ws, i, 7, round(x["amount"], 6), F_INPUT, NUM)
        put(ws, i, 5, "=MAX(G%d,0)" % i, fmt=NUM); put(ws, i, 6, "=MAX(-G%d,0)" % i, fmt=NUM)
        put(ws, i, 8, desc.get((x["entity"], x["account"]), ""))
        put(ws, i, 9, "=ROUND(G%d-(%r),2)" % (i, inp.get((x["entity"], x["account"]), 0.0)), fmt=NUM); ws.cell(row=i, column=9).fill = FILL_CHECK
    n_top = len(top_rows) + 1
    put(ws, n_top + 1, 4, "check", F_BOLD); put(ws, n_top + 1, 7, "=SUM(G2:G%d)" % n_top, fmt=NUM); ws.cell(row=n_top + 1, column=7).fill = FILL_CHECK
    put(ws, n_top + 1, 9, "=MAX(MAX(I2:I%d),-MIN(I2:I%d))" % (n_top, n_top), F_BOLD, NUM); ws.cell(row=n_top + 1, column=9).fill = FILL_CHECK
    check_cells.append(("topside_sums_to_zero", "Topside", "G%d" % (n_top + 1)))
    check_cells.append(("topside_vs_inputs", "Topside", "I%d" % (n_top + 1)))
    keys_all = set(inp) | {(x["entity"], x["account"]) for x in top_rows}
    exp_top = defaultdict(float)
    for x in top_rows:
        exp_top[(x["entity"], x["account"])] += x["amount"]
    py_checks["topside_vs_inputs"] = max(abs(exp_top.get(k, 0.0) - inp.get(k, 0.0)) for k in keys_all)
    py_checks["topside_sums_to_zero"] = sum(x["amount"] for x in top_rows)
    TOP = lambda c: "Topside!$%s$2:$%s$%d" % (c, c, n_top)

    # ------------------------------------------------------------------ ConsolTB
    ws = wb.create_sheet("ConsolTB")
    ct_cols = ["period", "ordinal", "account", "name", "statement", "entity layer", "IC eliminations", "CTA", "topside", "acquisition", "disposal", "equity method", "NCI attribution",
               "TOTAL (tool)", "Python replica", "diff (must be 0)"]
    head(ws, 1, ct_cols, [8, 6, 9, 40, 9, 14, 14, 13, 13, 13, 13, 13, 13, 15, 15, 12],
         {"entity layer": "sum of the group amounts (= translated, 100%) of the entity rows (Rows!Y) for the period and account",
          "IC eliminations": "the elimination legs of sheet IC for the period and account, in full",
          "equity method": "EQ_INCOME / EQ_INVEST of sheet EquityMethod: associate ABPT and joint venture ABJV (60%)",
          "NCI attribution": "the journals of sheet NCI attribution: Dr %s, Dr CTA, Cr %s" % (re_acct, nci_acct),
          "Python replica": "expected.json's figure for the same cell (static): the independent check that the formulas follow the warehouse's rules"})
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
            put(ws, r, 7, '=SUMIFS({ta},{p},$A{r},{aa},$C{r})+SUMIFS({tb},{p},$A{r},{ab},$C{r})+IF($C{r}="{dif}",SUMIFS({td},{p},$A{r}),0)'.format(
                ta=IC("Z"), tb=IC("AA"), td=IC("AB"), p=IC("A"), aa=IC("D"), ab=IC("F"), r=r, dif=d["policy"]["ic_difference_account"]), fmt=NUM)
            put(ws, r, 8, '=IF($C{r}="CTA",SUM(INDEX(CTA!$B$2:${lc}${n},0,MATCH($A{r},CTA!$B$1:${lc}$1,0))),0)'.format(r=r, lc=L(len(spine) + 1), n=n_cta), fmt=NUM)
            put(ws, r, 9, "=SUMIFS(%s,%s,$A%d,%s,$C%d)" % (TOP("G"), TOP("B"), r, TOP("D"), r), fmt=NUM)
            put(ws, r, 10, '=IF($A{r}="{ap}",SUMIFS({b},{a},$C{r}),0)'.format(r=r, ap=pl(acq["period"]), b=ACQ_B, a=ACQ_A), fmt=NUM)
            put(ws, r, 11, '=IF($A{r}="{dp}",SUMIFS({b},{a},$C{r}),0)'.format(r=r, dp=pl(dsp["period"]), b=DSP_B, a=DSP_A), fmt=NUM)
            put(ws, r, 12, '=IF($C{r}="EQ_INCOME",SUMIFS({g},{p},$A{r}),IF($C{r}="EQ_INVEST",SUMIFS({h},{p},$A{r}),0))'.format(r=r, g=EQ("G"), h=EQ("H"), p=EQ("A")), fmt=NUM)
            put(ws, r, 13, '=IF($C{r}="{re}",SUMIFS({j},{p},$A{r}),IF($C{r}="CTA",SUMIFS({k},{p},$A{r}),IF($C{r}="{nci}",SUMIFS({l},{p},$A{r}),0)))'.format(
                r=r, re=re_acct, nci=nci_acct, j=NA("J"), k=NA("K"), l=NA("L"), p=NA("B")), fmt=NUM)
            put(ws, r, 14, "=SUM(F%d:M%d)" % (r, r), F_BOLD, NUM)
            put(ws, r, 15, round(exp_fctb.get((pl(p), a), 0.0), 6), F_INPUT, NUM)
            put(ws, r, 16, "=ROUND(N%d-O%d,2)" % (r, r), fmt=NUM); ws.cell(row=r, column=16).fill = FILL_CHECK
            r += 1
    ct_last = r - 1
    CT = lambda c: "ConsolTB!$%s$%d:$%s$%d" % (c, ct_first, c, ct_last)
    put(ws, r + 1, 4, "checks over every period", F_BOLD)
    put(ws, r + 2, 4, "sum of every layer (must be 0)"); put(ws, r + 2, 14, "=ROUND(SUM(N%d:N%d),2)" % (ct_first, ct_last), fmt=NUM); ws.cell(row=r + 2, column=14).fill = FILL_CHECK
    put(ws, r + 3, 4, "largest difference to the Python replica"); put(ws, r + 3, 16, "=MAX(MAX(P%d:P%d),-MIN(P%d:P%d))" % (ct_first, ct_last, ct_first, ct_last), fmt=NUM); ws.cell(row=r + 3, column=16).fill = FILL_CHECK
    ct_check_rows = (r + 2, r + 3)
    check_cells.append(("every_layer_nets_to_zero", "ConsolTB", "N%d" % (r + 2)))
    check_cells.append(("formulas_vs_replica", "ConsolTB", "P%d" % (r + 3)))
    fresh = defaultdict(float)
    for (q, e, a, t), v in o.fctb.items():
        fresh[(pl(q), a)] += v
    py_checks["formulas_vs_replica"] = max(abs(fresh.get(k, 0.0) - exp_fctb.get(k, 0.0)) for k in set(fresh) | set(exp_fctb))
    py_checks["every_layer_nets_to_zero"] = max(abs(v) for v in exp["net_check"].values())

    # ------------------------------------------------------------------ Statements
    ws = wb.create_sheet("Statements")
    ws.column_dimensions["A"].width = 56
    for j in range(2, len(spine) + 4):
        ws.column_dimensions[L(j)].width = 14
    put(ws, 1, 1, "Consolidated statements of the Aquila Bike Group (EUR)", F_TITLE)
    put(ws, 2, 1, "Credit-positive presentation: revenue, profit and equity positive; costs and assets as the reader expects. One view: the IFRS 10 presentation the tool produces, "
                  "every controlled subsidiary line by line at 100%% and the minority as one NCI line (account %s)." % nci_acct)
    ws.cell(row=2, column=1).alignment = WRAP; ws.row_dimensions[2].height = 30
    hdr = ["line"] + [pl(p) for p in spine] + ["FY2024"]
    fy_cols = [j for j, p in enumerate(spine, 2) if p[0] == 2024]
    row_hdr = 0

    def sum_line(row, pred, sign=1, cumulative=False):
        for j, p in enumerate(spine, 2):
            cond = '%s,"<="&%d' % (CT("B"), ord_of[p]) if cumulative else '%s,%s$%d' % (CT("A"), L(j), row_hdr)
            put(ws, row, j, "=%d*SUMIFS(%s,%s,%s)" % (sign, CT("N"), cond, pred), fmt=NUM)
        if not cumulative:
            put(ws, row, len(spine) + 2, "=SUM(%s%d:%s%d)" % (L(fy_cols[0]), row, L(fy_cols[-1]), row), F_BOLD, NUM)

    def pnl_block(top, title):
        nonlocal row_hdr
        put(ws, top, 1, title, F_H2)
        row_hdr = top + 1
        head(ws, row_hdr, hdr, None)
        ws.freeze_panes = None
        lines = [("Revenue", '%s,"4*"' % CT("C"), -1), ("Cost of sales", '%s,"5*"' % CT("C"), -1), ("Operating expenses", '%s,"6*"' % CT("C"), -1),
                 ("Financial items", '%s,"7*"' % CT("C"), -1), ("Share of result of associates and joint ventures (EQ_INCOME)", '%s,"EQ_INCOME"' % CT("C"), -1),
                 ("Income taxes", '%s,"8*"' % CT("C"), -1)]
        rr = row_hdr + 1
        first = rr
        for name, pred, sign in lines:
            put(ws, rr, 1, name); sum_line(rr, pred, sign); rr += 1
        put(ws, rr, 1, "Net result for the period (100%)", F_BOLD)
        for j in range(2, len(spine) + 3):
            put(ws, rr, j, "=SUM(%s%d:%s%d)" % (L(j), first, L(j), rr - 1), F_BOLD, NUM)
        return rr

    def bs_block(top, title):
        nonlocal row_hdr
        put(ws, top, 1, title, F_H2)
        row_hdr = top + 1
        head(ws, row_hdr, hdr[:-1], None)
        ws.freeze_panes = None
        rr = row_hdr + 1
        first = rr
        put(ws, rr, 1, "Assets (1xxx, EQ_INVEST)"); sum_line(rr, '%s,"1*"' % CT("C"), 1, True)
        for j, p in enumerate(spine, 2):
            ws.cell(row=rr, column=j).value = ws.cell(row=rr, column=j).value + '+SUMIFS(%s,%s,"<="&%d,%s,"EQ_INVEST")' % (CT("N"), CT("B"), ord_of[p], CT("C"))
        rr += 1
        put(ws, rr, 1, "Liabilities (2xxx)"); sum_line(rr, '%s,"2*"' % CT("C"), -1, True); rr += 1
        put(ws, rr, 1, "Net assets", F_BOLD)
        for j in range(2, len(spine) + 2):
            put(ws, rr, j, "=%s%d-%s%d" % (L(j), first, L(j), first + 1), F_BOLD, NUM)
        na = rr; rr += 1
        put(ws, rr, 1, "Share capital, premium, reserves, retained earnings (3xxx) - owners")
        for j, p in enumerate(spine, 2):
            put(ws, rr, j, '=-(SUMIFS({v},{b},"<="&{o},{c},"3*")-SUMIFS({v},{b},"<="&{o},{c},"{nci}"))'.format(v=CT("N"), b=CT("B"), o=ord_of[p], c=CT("C"), nci=nci_acct), fmt=NUM)
        rr += 1
        put(ws, rr, 1, "Currency translation adjustment (CTA) - owners"); sum_line(rr, '%s,"CTA"' % CT("C"), -1, True); rr += 1
        put(ws, rr, 1, "Result not yet closed to retained earnings (P&L accounts, all years)")
        for j, p in enumerate(spine, 2):
            put(ws, rr, j, '=-SUMIFS({v},{b},"<="&{o},{s},"PL")'.format(v=CT("N"), b=CT("B"), o=ord_of[p], s=CT("E")), fmt=NUM)
        rr += 1
        put(ws, rr, 1, "Non-controlling interests (%s): the minority's share of ABSE's net assets" % nci_acct)
        sum_line(rr, '%s,"%s"' % (CT("C"), nci_acct), -1, True); rr += 1
        put(ws, rr, 1, "Total equity", F_BOLD)
        for j in range(2, len(spine) + 2):
            put(ws, rr, j, "=SUM(%s%d:%s%d)" % (L(j), na + 1, L(j), rr - 1), F_BOLD, NUM)
        te = rr; rr += 1
        put(ws, rr, 1, "check: net assets - total equity (must be 0)")
        for j in range(2, len(spine) + 2):
            put(ws, rr, j, "=ROUND(%s%d-%s%d,2)" % (L(j), na, L(j), te), fmt=NUM); ws.cell(row=rr, column=j).fill = FILL_CHECK
        return rr

    end1 = pnl_block(4, "Profit and loss (100%, then attributed)")
    put(ws, end1 + 1, 1, "  of which attributable to non-controlling interests")
    for j, p in enumerate(spine, 2):
        put(ws, end1 + 1, j, "=-SUMIFS(%s,%s,%s$%d)" % (NA("G"), NA("B"), L(j), row_hdr), fmt=NUM)
    put(ws, end1 + 1, len(spine) + 2, "=SUM(%s%d:%s%d)" % (L(fy_cols[0]), end1 + 1, L(fy_cols[-1]), end1 + 1), fmt=NUM)
    put(ws, end1 + 2, 1, "  of which attributable to the owners of the parent", F_BOLD)
    for j in range(2, len(spine) + 3):
        put(ws, end1 + 2, j, "=%s%d-%s%d" % (L(j), end1, L(j), end1 + 1), F_BOLD, NUM)
    end2 = bs_block(end1 + 4, "Balance sheet at period end (100% line by line, NCI line)")
    bs_check_row = end2
    nb = end2 + 2
    put(ws, nb, 1, "NCI: how the tool computes it", F_H2)
    note = ("ABSE is carried at 100%% line by line; the minority is one line, account %s. Opening NCI comes from the opening consolidation journal (for an acquired subsidiary, "
            "from the acquisition journal). Each period the attribution journal NCI-AQBIKE-ABSE-<year>-P<n> moves 30%% of ABSE's result (Dr retained earnings %s) and of its CTA movement "
            "(Dr CTA) to %s (sheet NCI attribution). Closing NCI is therefore 30%% of ABSE's net assets at the closing rate. Intercompany eliminations are in full: no NCI leg, "
            "so ABSE's sales to and from the group are eliminated at 100%% and the minority's share of the result is its share of ABSE's own profit." % (nci_acct, re_acct, nci_acct))
    c = put(ws, nb + 1, 1, note); c.alignment = WRAP
    ws.merge_cells(start_row=nb + 1, start_column=1, end_row=nb + 1, end_column=10); ws.row_dimensions[nb + 1].height = 75
    for k, (lab, key) in enumerate((("Opening NCI (opening journal CJ-OPEN-2023)", "opening"), ("Attributions FY2023 P12 to FY2024 P12", "attrib"), ("Closing NCI at 2024-12", "closing")), nb + 2):
        put(ws, k, 1, lab); put(ws, k, 2, "=" + nci_roll_cells[key], F_LINK, NUM)
    stmt_rows = {"pnl_result": end1, "bs_check": bs_check_row}

    # ------------------------------------------------------------------ Walkthrough
    ws = wb.create_sheet("Walkthrough", 1)
    ws.column_dimensions["A"].width = 10; ws.column_dimensions["B"].width = 70; ws.column_dimensions["C"].width = 18; ws.column_dimensions["D"].width = 60
    put(ws, 1, 1, "The year in nine steps: what to say, and the number to point at", F_TITLE)
    head(ws, 3, ["step", "talk track", "figure (EUR)", "where it comes from"], None)
    ws.freeze_panes = None

    def stmt(row, p):
        return "=Statements!%s%d" % (L(spine.index(p) + 2), row)
    end1, end2 = stmt_rows["pnl_result"], stmt_rows["bs_check"]
    steps = [
        ("1 Jan 2024", "We start from the FY2023 year-end trial balances of nine consolidated companies, one associate and (from P1) one joint venture, in five currencies. The holding's investments in its subsidiaries are eliminated against their share capital by the opening consolidation journal, which also opens ABSE's minority (Cr 3700); the balance sheet balances with the translation difference (CTA).",
         stmt(end2 - 1, (2023, 13)), "Statements: total equity at 2023-13 (after the year-end close moved the FY2023 result to retained earnings)"),
        ("FY2023 result", "The FY2023 result sits in the P&L accounts of the P12 file; the warehouse closes it to retained earnings in the Closing period (2023-13), translated at the 2023 annual average rate declared on FY2023 P12.",
         stmt(end1, (2023, 12)), "Statements: net result 2023-12"),
        ("P1-P5", "Each month: balances at the month's closing rate, movements of the P&L at the month's average rate, share capital at historical rates. ABSE is at 100% and its minority is attributed by a journal; the joint venture ABJV is picked up at 60%. Intercompany receivables equal payables after translation to the cent, so the eliminations leave nothing in the difference account.",
         "=0", "ConsolTB / IC: every pair matched (IC!S)"),
        ("P6: acquisition", "ABCZ acquired for EUR 11.0m. Goodwill = consideration - (net assets at book + fair value step-up), at the June closing rate. The 31 May balance sheet enters through the journal; ABCZ's own June movements through the entity layer. Costs expensed.",
         "=" + acq_gw_cell, "Acquisition: goodwill line"),
        ("P7-P11", "ABCZ consolidated like everyone else; management fees to ABCZ start; its balances now retranslate to each month's closing rate with the difference in CTA.",
         "=CTA!%s%d" % (L(ord_of[(2024, 9)] + 1), 2 + cons_ents.index("ABCZ")), "CTA: ABCZ 2024-9"),
        ("P12: disposal", "ABDK sold for EUR 7.0m on 31 December. Its net assets leave at the December closing rate, its accumulated CTA is recycled through the result, the proceeds land on the settlement account: gain on disposal.",
         "=" + dsp_gain_cell, "Disposal: gain (credit positive)"),
        ("FY2024 P&L", "Twelve months at monthly average rates, ABCZ from June, ABDK for the whole year (IFRS 10.B98: the results to the date of disposal stay in the group). Net result at 100%; the minority's part is shown beneath it.",
         "=Statements!%s%d" % (L(len(spine) + 2), end1), "Statements: FY2024 net result (100%)"),
        ("31 Dec 2024", "The consolidated balance sheet: goodwill on ABCZ, no ABDK, CTA in equity, the NCI line at 30% of ABSE's net assets, the result of the year still open until the FY2024 close.",
         stmt(end2 - 1, (2024, 12)), "Statements: total equity 2024-12"),
        ("Go back", "Every period's movements are kept. Period 6 or 7 is read the same way as period 12: in this workbook by column, in konsol with =K.EPM(\"AQBIKE\", 2024, 7, account, \"consolidated_amount\", \"consolidated\") (sheet LiveCheck).",
         stmt(end1, (2024, 7)), "Statements: net result 2024-7"),
    ]
    for i, (step, talk, fig, src) in enumerate(steps, 4):
        put(ws, i, 1, step, F_BOLD); c = put(ws, i, 2, talk); c.alignment = WRAP; ws.row_dimensions[i].height = 60
        put(ws, i, 3, fig, F_LINK, NUM); put(ws, i, 4, src).alignment = WRAP
    # a cleaner P1-P5 figure: the intercompany difference account balance at 2024-5 (must be ~0)
    ws.cell(row=6, column=3).value = '=SUMIFS(%s,%s,"2024-5",%s,"%s")' % (CT("N"), CT("A"), CT("C"), d["policy"]["ic_difference_account"])
    ws.cell(row=6, column=4).value = "ConsolTB: intercompany difference account 6750 in 2024-5 (nothing: every pair matched)"
    k = len(steps) + 5
    put(ws, k, 1, "Checks", F_H2)
    checks = [("Every layer of every period nets to zero", "=ConsolTB!N%d" % ct_check_rows[0]),
              ("Largest difference between these formulas and the Python replica", "=ConsolTB!P%d" % ct_check_rows[1]),
              ("Balance sheet balances in every period (sum of the check row)", "=SUM(Statements!B%d:%s%d)" % (stmt_rows["bs_check"], L(len(spine) + 1), stmt_rows["bs_check"])),
              ("Closing NCI less 30% of ABSE's net assets at the closing rate", "=" + nci_roll_cells["check"]),
              ("Opening journal lines less inputs.json", "=Topside!I%d" % (n_top + 1))]
    for i, (what, f) in enumerate(checks, k + 1):
        put(ws, i, 2, what); c = put(ws, i, 3, f, F_BOLD, NUM); c.fill = FILL_CHECK
        check_cells.append(("walkthrough: " + what, "Walkthrough", "C%d" % i))
    py_checks["balance_sheet_balances"] = max(abs(v) for v in exp["net_check"].values())

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
            put(ws, rr, 3, '=SUMIFS(%s,%s,"%s",%s,"%s")' % (CT("N"), CT("A"), pl(p), CT("C"), a), F_LINK, NUM)
            put(ws, rr, 4, '=K.EPM("%s", %d, %d, "%s", "consolidated_amount", "consolidated")' % (d["group"], p[0], p[1], a))
            ws.cell(row=rr, column=4).data_type = "s"   # keep as text
            rr += 1
    put(ws, rr + 1, 1, "A balance-sheet balance is the sum of the movements from 2023-12 to the period (K.EPM returns movements; add the periods, or read the Rows sheet's logic).").alignment = WRAP
    ws.merge_cells(start_row=rr + 1, start_column=1, end_row=rr + 1, end_column=4)

    wb.save(OUT)
    print("wrote %s  (TB %d rows, Rows %d, IC %d, ConsolTB %d)" % (os.path.relpath(OUT, HERE), n_tb - 1, n_rows - 1, n_ic - 1, ct_last - ct_first + 1))
    return {"cells": check_cells, "python": py_checks, "figures": figures}


if __name__ == "__main__":
    build()
