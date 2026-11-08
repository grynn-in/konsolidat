#!/usr/bin/env python3
"""Offline consolidation of the Aquila Bike example: a from-scratch replica of what the konsolidat
warehouse computes, written from the dbt models (silver_tb_movements, gold_consolidated_trial_balance,
gold_fx_revaluation, gold_entity_ownership, gold_ic_reconciliation / gold_ic_eliminations,
gold_business_combination_journal, gold_business_disposal_journal, gold_equity_method_associates,
gold_consolidation_adjustments, gold_nci_attribution_journal, gold_fully_consolidated_tb, and the pair 1
ownership_resolution macro), so the Excel walkthrough and the live
build can both be compared with it to the cent.

    uv run aquila_bike_offline.py          -> examples/aquila-bike/model/expected.json + a summary

It reads model/inputs.json written by build_aquila_bike.py. Rules followed (konsol#117 pair 2, konsolidat#204
option (a), decided by Deepak Pai 7-8 Nov 2026): a full subsidiary is consolidated at 100% (group_amount =
translated_amount); intercompany is eliminated in full; the minority is one NCI line, posted per period by the
attribution journal (result share + CTA share); ownership is the sum of the paths and a multi-path entity takes the
group's declared method; an associate's pickup ignores the year-end close rows. Where the warehouse's rule is a product
gap, this file says so in a comment and follows the warehouse (never a "better" rule).
"""
from __future__ import annotations

import datetime as dt
import json
import os
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
MODEL_DIR = os.path.join(HERE, "examples", "aquila-bike", "model")
FLOOR = 0.005          # macros/materiality.sql


def load_inputs():
    with open(os.path.join(MODEL_DIR, "inputs.json")) as f:
        return json.load(f)


class Offline:
    def __init__(self, d):
        self.d = d
        self.group = d["group"]
        self.gcur = d["group_currency"]
        self.periods = [tuple(p) for p in d["periods"]]
        self.ent = d["entities"]
        self.chart = d["chart"]
        self.rates = {tuple(int(x) for x in k.split("-")): v for k, v in d["rates"].items()}
        self.hist = d["hist_rates"]
        self.ic_pairs = [tuple(p) for p in d["ic_pairs"]]
        self.policy = d["policy"]
        self.acq = d["acquisition"]
        self.dsp = d["disposal"]
        self.acq["period"] = tuple(self.acq["period"])
        self.acq["pre_period"] = tuple(self.acq["pre_period"])
        self.dsp["period"] = tuple(self.dsp["period"])
        self.close_period = (2023, 13)
        self.links = d["ownership_links"]
        self.declarations = d["declarations"]
        self._resolved = {}
        # balances (period-end, local cents) per entity, key (account, partner), period
        self.bal = defaultdict(lambda: defaultdict(dict))
        for e, y, p, a, partner, c in d["tb_cents"]:
            self.bal[e][(a, partner)][(y, p)] = c
        self.claimed = {e: sorted({p for k in keys for p in keys[k]}) for e, keys in self.bal.items()}
        self.counterpart = {}
        for a, b in self.ic_pairs:
            self.counterpart[a] = b
            self.counterpart[b] = a

    # ---- chart facts -----------------------------------------------------------------------------
    def acct(self, a):
        return self.chart.get(a) or {"type": "", "flags": ""}

    def is_pnl(self, a):
        return self.acct(a)["type"] in ("Revenue", "Expense")

    def is_bs(self, a):
        return self.acct(a)["type"] in ("Asset", "Liability", "Equity")

    def is_equity(self, a):
        return self.acct(a)["type"] == "Equity"

    def fx_method(self, a):
        if self.is_pnl(a):
            return "average"
        return "historical" if "hist" in self.acct(a)["flags"].split() else "closing"

    def is_re(self, a):
        return "RE" in self.acct(a)["flags"].split()

    # ---- calendar helpers ------------------------------------------------------------------------
    @staticmethod
    def period_date(p):
        return dt.date(p[0], min(max(p[1], 1), 12), 1)          # build_date_from_year_period

    def rate_period(self, p):
        return (p[0], 12) if p[1] == 13 else p                      # a Closing period uses the last Regular period's rates

    def closing(self, cur, p):
        return 1.0 if cur == self.gcur else self.rates[self.rate_period(p)]["Closing"][cur]

    def average(self, cur, p):
        return 1.0 if cur == self.gcur else self.rates[self.rate_period(p)]["Average"][cur]

    # ---- 1. silver_tb_movements -----------------------------------------------------------------
    def movements(self):
        """{entity: {period: {(account, partner): (movement_cents, has_source, is_close)}}}"""
        out = defaultdict(lambda: defaultdict(dict))
        for e, keys in self.bal.items():
            spine = list(self.claimed[e])
            closes = [p for p in spine if p[0] == 2023]
            has_close = bool(closes) and max(spine)[0] > 2023
            if has_close:
                last23 = max(closes)
                spine = sorted(spine + [self.close_period])
                pnl_total = sum(keys[k].get(last23, 0) for k in keys if self.is_pnl(k[0]))
            allkeys = set(keys)
            if has_close:
                allkeys.add(("3300", ""))
            for k in allkeys:
                prev = 0
                for p in spine:
                    if p == self.close_period:
                        if self.is_pnl(k[0]):
                            b, src = 0, False
                        elif k == ("3300", ""):
                            b, src = keys.get(k, {}).get(last23, 0) + pnl_total, True
                        else:
                            b, src = keys.get(k, {}).get(last23, 0), False
                        is_close = True
                    else:
                        b = keys.get(k, {}).get(p, 0)
                        src = p in keys.get(k, {})
                        is_close = False
                    mov = b - prev
                    prev = b
                    if mov == 0 and not src:
                        continue
                    out[e][p][k] = (mov, src, is_close)
        return out

    # ---- 2. ownership window --------------------------------------------------------------------
    # DECLARATION_TRIGGER_PCT in macros/ownership_resolution.sql: above it, several paths with no all-full path need a declaration.
    DECLARATION_TRIGGER_PCT = 50
    RANK = {"full": 1, "proportional": 2, "equity": 3, "none": 4}
    NAME = {1: "full", 2: "proportional", 3: "equity", 4: "none"}

    def _link_live(self, link, d):
        if d < dt.date.fromisoformat(link["since"]):
            return False
        # the disposal closes the disposed entity's links on its date (Business Disposal)
        return not (link["entity"] == self.dsp["entity"] and d > dt.date.fromisoformat(self.dsp["date"]))

    def _paths(self, e, d):
        """[(product of link pcts, weakest-method rank)] per path from the group to `e` at date d."""
        out = []
        for link in self.links:
            if link["entity"] != e or not self._link_live(link, d):
                continue
            rank = self.RANK.get(link["method"], 4)
            if link["owner"] == "":
                out.append((link["pct"] / 100.0, rank))
            else:
                out += [(link["pct"] / 100.0 * pp, max(rank, rr)) for pp, rr in self._paths(link["owner"], d)]
        return out

    def resolve(self, e, p):
        """Effective ownership and method of `e` in period p (the pair 1 ownership_resolution macro):
        eff = sum over paths of the product of link pcts; the method is the weakest link of the path(s), or, when
        several paths disagree or add past the trigger without an all-full path, the group's declaration for the
        date (undeclared -> none)."""
        key = (e, p)
        if key in self._resolved:
            return self._resolved[key]
        d = self.period_date(p)
        paths = self._paths(e, d)
        eff = sum(pp for pp, _ in paths)
        ranks = {rr for _, rr in paths}
        needs = len(paths) > 1 and (len(ranks) > 1 or (1 not in ranks and eff * 100 > self.DECLARATION_TRIGGER_PCT))
        if not paths:
            out = {"eff": 0.0, "method": "none", "source": "outside", "paths": 0}
        elif not needs:
            out = {"eff": eff, "method": self.NAME[max(ranks)], "source": "link", "paths": len(paths)}
        else:
            decl = [x for x in self.declarations if x["group"] == self.group and x["entity"] == e
                    and dt.date.fromisoformat(x["from"]) <= d and (not x["to"] or dt.date.fromisoformat(x["to"]) > d)]
            if decl:
                out = {"eff": eff, "method": decl[-1]["method"], "source": "declared", "paths": len(paths)}
            else:
                out = {"eff": eff, "method": "none", "source": "undeclared", "paths": len(paths)}
        self._resolved[key] = out
        return out

    def in_window(self, e, p):
        return bool(self._paths(e, self.period_date(p)))

    def consolidated(self, e, p):
        return self.resolve(e, p)["method"] in ("full", "proportional")

    def pct(self, e, p):
        return self.resolve(e, p)["eff"]

    def ic_share(self, e, p):
        """Elimination share of one side: the operator's share for a proportional entity, else 1.0 (as the warehouse)."""
        res = self.resolve(e, p)
        return res["eff"] if res["method"] == "proportional" else 1.0

    def ic_factor(self, ea, eb, p):
        """One factor per pair: least(share_a, share_b) (gold_ic_eliminations, konsol#117 pair 3)."""
        return min(self.ic_share(ea, p), self.ic_share(eb, p))

    # ---- 3. gold_consolidated_trial_balance -----------------------------------------------------
    def translate(self, mov):
        """rows: dicts with entity, period, account, partner, local, rate, retranslation, close_adj,
        translated, group, nci, is_close, is_filler."""
        rows = []
        for e in sorted(mov):
            cur = self.ent[e]["currency"]
            periods = [p for p in sorted(mov[e]) if self.consolidated(e, p)]      # the entity's spine in this group
            if not periods:
                continue
            # rated rows
            rated = defaultdict(dict)   # key -> period -> row
            for p in periods:
                for k, (cents, src, is_close) in mov[e][p].items():
                    a, partner = k
                    method = self.fx_method(a)
                    if method == "historical" and cur != self.gcur and self.period_date(p) >= dt.date.fromisoformat(self.ent[e]["since"]):
                        rate = self.hist[e]
                    elif method == "average":
                        rate = self.average(cur, p)
                    else:
                        rate = self.closing(cur, p)
                    rated[k][p] = {"entity": e, "period": p, "account": a, "partner": partner, "local": cents / 100.0,
                                   "rate": rate, "retranslation": 0.0, "close_adj": 0.0, "is_close": is_close, "is_filler": False}
            # fillers + retranslation for balance-sheet, non-equity, closing-rate keys
            for k, byp in rated.items():
                a = k[0]
                if not (self.is_bs(a) and not self.is_equity(a) and self.fx_method(a) == "closing"):
                    continue
                first = min(byp)
                for p in periods:
                    if p > first and p not in byp:
                        byp[p] = {"entity": e, "period": p, "account": a, "partner": k[1], "local": 0.0,
                                  "rate": self.closing(cur, p), "retranslation": 0.0, "close_adj": 0.0, "is_close": False, "is_filler": True}
                cum, prev_c = 0.0, None
                for p in sorted(byp):
                    r = byp[p]
                    c = self.closing(cur, p)
                    if prev_c is not None:
                        r["retranslation"] = cum * (c - prev_c)
                    cum += r["local"]
                    prev_c = c
            # year-end close adjustments (konsolidat#259)
            for k, byp in rated.items():
                for p, r in byp.items():
                    if r["is_close"] and self.is_pnl(r["account"]):
                        before = [x for q, x in byp.items() if q[0] == p[0] and q < p]
                        r["close_adj"] = sum(x["local"] for x in before) * r["rate"] - sum(x["local"] * x["rate"] + x["retranslation"] for x in before)
            re_key = ("3300", "")
            for p in periods:
                if p[1] == 13 and p in rated.get(re_key, {}):
                    r = rated[re_key][p]
                    pnl_rows = [rated[k][p] for k in rated if p in rated[k] and rated[k][p]["is_close"] and self.is_pnl(k[0])]
                    r["close_adj"] = sum(x["local"] for x in pnl_rows) * r["rate"] - sum(x["local"] * x["rate"] + x["close_adj"] for x in pnl_rows)
            for k, byp in rated.items():
                for p, r in byp.items():
                    adj = r["retranslation"] + r["close_adj"]
                    pct = self.pct(e, p)
                    r["translated"] = r["local"] * r["rate"] + adj
                    if self.resolve(e, p)["method"] == "proportional":
                        # konsol#117 pair 3 (IFRS 11 joint operation): the operator's share of each line, no NCI
                        r["group"] = r["translated"] * pct
                        r["nci"] = 0.0
                    else:
                        r["group"] = r["translated"]                  # K1: 100%, whatever the group's share
                        r["nci"] = r["translated"] * (1 - pct)        # the attribution amount, not the complement
                    rows.append(r)
        return rows

    # ---- 4. gold_fx_revaluation -----------------------------------------------------------------
    @staticmethod
    def cta(rows):
        out = defaultdict(float)
        for r in rows:
            out[(r["entity"], r["period"])] -= r["group"]
        return out

    # ---- 5. intercompany ------------------------------------------------------------------------
    def ic(self, rows, mov):
        sides = defaultdict(lambda: [0.0, 0.0, 0.0])    # (period, entity, partner, account, counterpart) -> local, translated, group
        for r in rows:
            if r["partner"] and r["partner"] != r["entity"] and r["account"] in self.counterpart:
                s = sides[(r["period"], r["entity"], r["partner"], r["account"], self.counterpart[r["account"]])]
                s[0] += r["local"]; s[1] += r["translated"]; s[2] += r["group"]
        pair_moves = defaultdict(lambda: defaultdict(lambda: {"la": 0.0, "lb": 0.0, "ta": 0.0, "tb": 0.0, "ga": 0.0, "gb": 0.0, "is_bs": 0}))
        for (p, e, partner, a, cp), (loc, tr, gr) in sides.items():
            is_a = (e, a) < (partner, cp)
            pair = (e, a, partner, cp) if is_a else (partner, cp, e, a)
            pm = pair_moves[pair][p]
            if is_a:
                pm["la"] += loc; pm["ta"] += tr; pm["ga"] += gr
            else:
                pm["lb"] += loc; pm["tb"] += tr; pm["gb"] += gr
            pm["is_bs"] = max(pm["is_bs"], 1 if self.is_bs(a) else 0)
        spine_periods = sorted({p for e in mov for p in mov[e]})
        last = max(p for e in mov for p in mov[e] if self.consolidated(e, p))
        recon, elims = [], []
        for pair, byp in sorted(pair_moves.items()):
            ea, aa, eb, ab = pair
            first = min(byp)
            spine = [p for p in spine_periods if first <= p <= last]
            pair_is_bs = max(v["is_bs"] for v in byp.values())
            prev_live = 0
            cum = {"la": 0.0, "lb": 0.0, "ta": 0.0, "tb": 0.0, "ga": 0.0, "gb": 0.0}
            valued = []
            for p in spine:
                live = 1 if (self.consolidated(ea, p) and self.consolidated(eb, p)) else 0
                out = 1 if (live == 0 and prev_live == 1) else 0
                was_live = prev_live
                m = byp.get(p)
                has_move = 1 if m else 0
                mv = m or {"la": 0.0, "lb": 0.0, "ta": 0.0, "tb": 0.0, "ga": 0.0, "gb": 0.0}
                for c in cum:
                    cum[c] += mv[c]
                keep = ((pair_is_bs and ((live and (has_move or not was_live)) or (out and was_live)))
                        or (not pair_is_bs and live and has_move))
                if keep:
                    if pair_is_bs:
                        vals = {c: (0.0 if out else cum[c]) for c in cum}
                        event = "left" if out else ("joined" if not was_live else "")
                    else:
                        vals = dict(mv)
                        event = ""
                    valued.append((p, vals, event))
                prev_live = live
            prev_post = None
            for p, v, event in valued:
                ta, tb_, ga, gb, la, lb = v["ta"], v["tb"], v["ga"], v["gb"], v["la"], v["lb"]
                share_a = ga / ta if abs(ta) >= FLOOR else 1.0
                share_b = gb / tb_ if abs(tb_) >= FLOOR else 1.0
                matched = min(abs(ta), abs(tb_)) if ta * tb_ < 0 else 0.0
                sgn = lambda x: (x > 0) - (x < 0)
                res_a = ta - sgn(ta) * matched
                res_b = tb_ - sgn(tb_) * matched
                cur_a, cur_b = self.ent[ea]["currency"], self.ent[eb]["currency"]
                if abs(ta + tb_) < FLOOR:
                    cause = "none"
                elif cur_a != cur_b:
                    cause = "fx"
                elif abs(la + lb) >= FLOOR:
                    cause = "booking"
                else:
                    cause = "fx"
                full_a, full_b = -sgn(ta) * matched, -sgn(tb_) * matched
                # K3: in full - the matched amount on each side and the full residual; no NCI leg
                f = self.ic_factor(ea, eb, p)       # 1.0 unless a side is a joint operation (pair 3)
                comp = {"m_a": full_a * f, "m_b": full_b * f, "d_a": -res_a * f, "d_b": -res_b * f}
                post = {c: comp[c] - (prev_post[c] if (pair_is_bs and prev_post) else 0.0) for c in comp}
                prev_post = comp
                tol = self.policy["ic_difference_tolerance"]
                status = ("matched" if cause == "none" else
                          "fx_difference" if (cause == "fx" and not (pair_is_bs and cur_a != cur_b)) else
                          "within_tolerance" if abs(ta + tb_) <= tol else "over_tolerance")
                recon.append({"period": p, "entity_a": ea, "account_a": aa, "entity_b": eb, "account_b": ab,
                              "basis": "balance" if pair_is_bs else "movement", "event": event, "local_a": la, "local_b": lb,
                              "translated_a": ta, "translated_b": tb_, "share_a": share_a, "share_b": share_b, "matched": matched,
                              "difference": ta + tb_, "cause": cause, "status": status})
                diff_acct = self.policy["ic_difference_account"]
                legs = [("matched", aa, post["m_a"], ab),
                        ("difference", aa, post["d_a"], diff_acct),
                        ("difference", ab, post["d_b"], diff_acct)]
                for kind, acc1, v1, acc2 in legs:
                    if abs(v1) < FLOOR:
                        continue
                    for acc, amt in ((acc1, v1), (acc2, -v1)):
                        elims.append({"period": p, "kind": kind, "pair": "IC:%s/%s" % (aa, ab), "account": acc, "entity": "",
                                      "amount": amt, "type": "ic_elimination", "entity_a": ea, "entity_b": eb})
        return recon, elims

    # ---- 6. deal journals -----------------------------------------------------------------------
    def cum_local(self, mov, e, through, pred):
        """gold_trial_balance cumulative movements of `e` by account through `through` (inclusive), accounts where pred."""
        out = defaultdict(int)
        for p in mov[e]:
            if p <= through:
                for (a, partner), (cents, *_rest) in mov[e][p].items():
                    if pred(a):
                        out[a] += cents
        return out

    def acquisition_journal(self, mov):
        e, p = self.acq["entity"], self.acq["period"]
        rate = self.closing(self.ent[e]["currency"], p)
        lines = []
        # (0) opening balances through the period before the acquisition period, at the acquisition closing rate
        if any(q < p for q in mov[e]):
            opening = self.cum_local(mov, e, (p[0], p[1] - 1), self.is_bs)
            total = 0.0
            for a in sorted(opening):
                if opening[a]:
                    amt = opening[a] / 100.0 * rate
                    lines.append({"line": 0, "role": "opening_balance", "account": a, "amount": amt})
                    total += amt
            if abs(total) >= FLOOR:
                lines.append({"line": 0, "role": "opening_balance", "account": "3300", "amount": -total})
        # (1) equity eliminated: the acquired balance sheet's equity rows, 100%
        net_assets = 0.0
        fva = 0.0
        for i, ab in enumerate(self.acq["acquired_balances"], start=1):
            book = float(ab["book_amount"]) * rate
            fva += float(ab["fair_value_adjustment"] or 0) * rate
            if self.is_equity(ab["main_account"]):
                lines.append({"line": i, "role": "equity_eliminated", "account": ab["main_account"], "amount": -book})
                net_assets -= book
        consideration = float(self.acq["consideration_eur"])          # EUR lines translate at 1
        goodwill_raw = consideration + 0.0 + 0.0 - (net_assets + fva)
        if abs(fva) >= FLOOR:
            lines.append({"line": 101, "role": "fva", "account": self.policy["fair_value_adjustment_account"], "amount": fva})
        lines.append({"line": 102, "role": "goodwill", "account": self.policy["goodwill_account"], "amount": max(goodwill_raw, 0.0)})
        lines.append({"line": 103, "role": "investment", "account": self.policy["investment_account"], "amount": -consideration})
        if goodwill_raw < 0:
            lines.append({"line": 105, "role": "bargain_gain", "account": self.policy["bargain_purchase_gain_account"], "amount": goodwill_raw})
        for i, (kind, amount) in enumerate(self.acq["costs_eur"], start=1):
            lines.append({"line": 110 + i, "role": "costs", "account": self.policy["acquisition_costs_account"], "amount": float(amount)})
            lines.append({"line": 130 + i, "role": "costs_settlement", "account": self.policy["disposal_proceeds_account"], "amount": -float(amount)})
        for l in lines:
            l.update({"entity": e, "period": p, "journal": "ACQ-%s-%s-%s" % (self.group, e, self.acq["date"]), "type": "acquisition"})
        self.acq_result = {"rate": rate, "net_assets": net_assets, "fva": fva, "goodwill": max(goodwill_raw, 0.0), "consideration": consideration}
        return lines

    def disposal_journal(self, mov, cta, acq_lines):
        e, p = self.dsp["entity"], self.dsp["period"]
        rate = self.closing(self.ent[e]["currency"], p)
        lines = []
        bal = self.cum_local(mov, e, p, lambda a: self.is_bs(a) and not self.is_equity(a))
        for a in sorted(bal):
            if bal[a]:
                lines.append({"line": 0, "role": "derecognised", "account": a, "amount": -bal[a] / 100.0 * rate})
        gw = sum(l["amount"] for l in acq_lines if l["entity"] == e and l["role"] == "goodwill")
        fva = sum(l["amount"] for l in acq_lines if l["entity"] == e and l["role"] == "fva")
        nci = sum(l["amount"] for l in acq_lines if l["entity"] == e and l["role"] == "nci")
        lines.append({"line": 101, "role": "goodwill", "account": self.policy["goodwill_account"], "amount": -gw})
        lines.append({"line": 102, "role": "fva", "account": self.policy["fair_value_adjustment_account"], "amount": -fva})
        acc_cta = sum(v for (ee, q), v in cta.items() if ee == e and q <= p)
        lines.append({"line": 103, "role": "cta", "account": "CTA", "amount": -acc_cta})
        lines.append({"line": 104, "role": "nci", "account": self.policy["nci_account"], "amount": -nci})
        lines.append({"line": 110, "role": "proceeds", "account": self.policy["disposal_proceeds_account"], "amount": float(self.dsp["proceeds_eur"])})
        lines.append({"line": 199, "role": "gain_loss", "account": self.policy["disposal_gain_loss_account"], "amount": -sum(l["amount"] for l in lines)})
        for l in lines:
            l.update({"entity": e, "period": p, "journal": "DSP-%s-%s-%s" % (self.group, e, self.dsp["date"]), "type": "disposal"})
        self.dsp_result = {"rate": rate, "net_assets": sum(bal[a] for a in bal) / 100.0 * rate, "cta_recycled": acc_cta}
        return lines

    # ---- 7. equity method (as the warehouse WOULD post once konsolidat's sign/currency issue is fixed:
    #         Dr EQ_INVEST / Cr EQ_INCOME = share of the period's result at the period's Average rate).
    #         The warehouse today posts both legs with the same sign and untranslated (issue filed 7 Nov 2026). ----
    def equity_method(self, mov):
        lines = []
        for e, info in self.ent.items():
            for p in sorted(mov[e]):
                if self.resolve(e, p)["method"] != "equity":
                    continue
                # the period's own activity: the synthesized year-end close rows are left out (konsolidat#279)
                net = sum(c for (a, _), (c, _src, is_close) in mov[e][p].items() if self.is_pnl(a) and not is_close) / 100.0
                amount = net * self.pct(e, p) * self.average(info["currency"], p)
                if abs(amount) <= 0.01:
                    continue
                jid = "EQ_%s_%s_%d_P%d" % (self.group, e, p[0], p[1])
                lines.append({"entity": e, "period": p, "account": "EQ_INCOME", "amount": amount, "type": "equity_method", "journal": jid})
                lines.append({"entity": e, "period": p, "account": "EQ_INVEST", "amount": -amount, "type": "equity_method", "journal": jid})
        return lines

    # ---- 7b. NCI attribution (gold_nci_attribution_journal, K2): the minority's share of a full subsidiary's
    #          result and CTA, per entity and period, from retained earnings and CTA to the NCI line ----
    def nci_attribution(self, rows, cta):
        re_accounts = sorted(a for a, v in self.chart.items() if "RE" in v["flags"].split())
        if not re_accounts:
            return []
        re_account, nci_account = re_accounts[0], self.policy["nci_account"]
        result = defaultdict(float)
        present = set()
        for r in rows:
            present.add((r["entity"], r["period"]))
            if self.is_pnl(r["account"]) and not r["is_close"]:
                result[(r["entity"], r["period"])] += r["nci"]
        lines = []
        for (e, p) in sorted(present):
            res = self.resolve(e, p)
            if res["method"] != "full" or res["eff"] >= 1 - 0.000001:
                continue
            result_share = result.get((e, p), 0.0)
            cta_share = (1 - res["eff"]) * cta.get((e, p), 0.0)
            if abs(result_share) <= 0.000001 and abs(cta_share) <= 0.000001:
                continue
            jid = "NCI-%s-%s-%d-P%d" % (self.group, e, p[0], p[1])
            for acct, amt, role in ((re_account, -result_share, "retained_earnings"), ("CTA", -cta_share, "cta"),
                                    (nci_account, result_share + cta_share, "nci")):
                if abs(amt) > 0.000001:
                    lines.append({"entity": e, "period": p, "account": acct, "amount": amt, "type": "nci_attribution",
                                  "journal": jid, "role": role})
        return lines

    # ---- 8. topside journals ---------------------------------------------------------------------
    def topside(self):
        lines = []
        for l in self.d["opening_journal"]:
            amt = float(l["debit_amount"] or 0) - float(l["credit_amount"] or 0)
            lines.append({"entity": l["data_area_id"], "period": (2023, 12), "account": l["main_account"], "amount": amt,
                          "type": "topside", "journal": l["journal_ref"]})
        return lines

    # ---- 9. gold_fully_consolidated_tb -----------------------------------------------------------
    def run(self):
        mov = self.movements()
        rows = self.translate(mov)
        cta = self.cta(rows)
        recon, elims = self.ic(rows, mov)
        acq = self.acquisition_journal(mov)
        dsp = self.disposal_journal(mov, cta, acq)
        eq = self.equity_method(mov)
        nci = self.nci_attribution(rows, cta)
        top = self.topside()
        fctb = defaultdict(float)   # (period, entity, account, type) -> amount
        for r in rows:
            fctb[(r["period"], r["entity"], r["account"], "entity")] += r["group"]
        for (e, p), v in cta.items():
            if abs(v) >= 0:
                fctb[(p, e, "CTA", "cta")] += v
        for l in elims:
            fctb[(l["period"], l["entity"], l["account"], l["type"])] += l["amount"]
        for l in acq + dsp + eq + nci + top:
            fctb[(l["period"], l["entity"], l["account"], l["type"])] += l["amount"]
        self.mov, self.rows, self.cta_by, self.recon, self.elims, self.acq_lines, self.dsp_lines, self.eq_lines, self.top_lines, self.fctb = \
            mov, rows, cta, recon, elims, acq, dsp, eq, top, fctb
        self.nci_lines = nci
        return self

    def statements(self):
        # quantise once (6 places, the precision expected.json carries) so every later sum adds the same numbers
        self.fctb = {k: round(v, 6) + 0.0 for k, v in self.fctb.items()}
        periods = sorted({k[0] for k in self.fctb})
        pnl_period, bs_cum, check = {}, {}, {}
        cum = defaultdict(float)
        for p in periods:
            pl = defaultdict(float)
            for (q, e, a, t), v in sorted(self.fctb.items()):    # sorted: float sums must not depend on insertion order
                if q == p:
                    cum[a] += v
                    if self.is_pnl(a) or a in ("EQ_INCOME",):
                        pl[a] += v
            pnl_period[p] = dict(pl)
            bs_cum[p] = {a: v for a, v in cum.items() if not (self.is_pnl(a) or a == "EQ_INCOME")}
            check[p] = sum(v for (q, *_), v in sorted(self.fctb.items()) if q == p)
        return periods, pnl_period, bs_cum, check

    def dump(self):
        periods, pnl, bs, check = self.statements()
        def pk(p): return "%d-%d" % p
        out = {
            "fctb": [{"period": pk(p), "entity": e, "account": a, "type": t, "amount": round(v, 6)} for (p, e, a, t), v in sorted(self.fctb.items()) if abs(v) >= 1e-9],
            "translation": [dict(r, period=pk(r["period"])) for r in self.rows],
            "cta": [{"entity": e, "period": pk(p), "amount": v} for (e, p), v in sorted(self.cta_by.items())],
            "ic_reconciliation": [dict(r, period=pk(r["period"])) for r in self.recon],
            "ic_eliminations": [dict(l, period=pk(l["period"])) for l in self.elims],
            "acquisition_journal": [dict(l, period=pk(l["period"])) for l in self.acq_lines],
            "acquisition_result": self.acq_result,
            "disposal_journal": [dict(l, period=pk(l["period"])) for l in self.dsp_lines],
            "disposal_result": self.dsp_result,
            "equity_method": [dict(l, period=pk(l["period"])) for l in self.eq_lines],
            "nci_attribution": [dict(l, period=pk(l["period"])) for l in self.nci_lines],
            "ownership": [dict(entity=e, period=pk(p), **self.resolve(e, p)) for e in sorted(self.ent) for p in self.periods
                          if self.resolve(e, p)["paths"]],
            "topside": [dict(l, period=pk(l["period"])) for l in self.top_lines],
            "pnl_period": {pk(p): v for p, v in pnl.items()},
            "bs_cumulative": {pk(p): v for p, v in bs.items()},
            "net_check": {pk(p): v for p, v in check.items()},
        }
        out = canonical(out)
        # a row that rounds to zero says nothing; dropping it AFTER rounding keeps float noise from deciding the row count
        for k in ("fctb", "cta"):
            out[k] = [r for r in out[k] if r["amount"] != 0]
        with open(os.path.join(MODEL_DIR, "expected.json"), "w") as f:
            json.dump(out, f, indent=1, sort_keys=True)
            f.write("\n")
        return out


def canonical(x):
    """expected.json is a pure function of inputs.json: floats rounded to 6 places (the precision of the warehouse's amounts, and coarse enough that float-summation noise cannot move a byte) with -0.0 as 0.0 (so a different
    summation order cannot change a byte), every list in its rows' sorted order, dict keys sorted at write time."""
    if isinstance(x, float):
        return round(x, 6) + 0.0
    if isinstance(x, dict):
        return {k: canonical(v) for k, v in x.items()}
    if isinstance(x, (list, tuple)):
        rows = [canonical(v) for v in x]
        return sorted(rows, key=lambda r: json.dumps(r, sort_keys=True))
    return x


def main():
    d = load_inputs()
    o = Offline(d).run()
    out = o.dump()
    periods, pnl, bs, check = o.statements()
    print("fully consolidated TB rows: %d" % len(out["fctb"]))
    print("net of every layer per period (must be 0):")
    for p in periods:
        print("  %d-%02d  %12.4f" % (p[0], p[1], check[p]))
    def total(p, pred):
        return sum(v for a, v in pnl[p].items() if pred(a))
    print("\nconsolidated P&L (EUR, credit positive): revenue / result")
    rev = res = 0.0
    for p in periods:
        if p[0] == 2024:
            r = -total(p, lambda a: a[0] == "4"); n = -total(p, lambda a: True)
            rev += r; res += n
            print("  %d-%02d  revenue %14.2f  result %14.2f" % (p[0], p[1], r, n))
    print("  FY2024  revenue %14.2f  result %14.2f" % (rev, res))
    fy23 = -sum(pnl[(2023, 12)].values())
    print("  FY2023 result (P12 file) %14.2f" % fy23)
    for p in ((2023, 12), (2023, 13), (2024, 6), (2024, 12)):
        b = bs[p]
        assets = sum(v for a, v in b.items() if a[0] == "1" or a == "EQ_INVEST")
        liab = -sum(v for a, v in b.items() if a[0] == "2")
        eq = -sum(v for a, v in b.items() if a[0] == "3" or a == "CTA")
        print("balance sheet %d-%02d: assets %14.2f liabilities %14.2f equity+CTA %14.2f open P&L %14.2f goodwill %12.2f CTA %12.2f NCI(3700) %12.2f" % (
            p[0], p[1], assets, liab, eq, -sum(v for q, pp in pnl.items() if q[0] == p[0] and q <= p for v in pp.values()),
            b.get("1121", 0), -b.get("CTA", 0), -b.get("3700", 0)))
    # NCI (3700): the opening journal's 30% of ABSE's equity + every period's attribution = 30% of ABSE's net assets
    last = max(periods)
    opening_nci = -sum(l["amount"] for l in o.top_lines if l["account"] == "3700")
    attributed = -sum(l["amount"] for l in o.nci_lines if l["account"] == "3700")
    net_assets = sum(r["translated"] for r in o.rows if r["entity"] == "ABSE" and o.is_bs(r["account"]) and not o.is_equity(r["account"]))
    minority = 1 - o.resolve("ABSE", last)["eff"]
    print("\nNCI(3700) %d-%02d: opening journal %.2f + attribution %.2f = %.2f ; %.0f%% x ABSE net assets (closing rate) %.2f ; difference %.4f" % (
        last[0], last[1], opening_nci, attributed, -bs[last].get("3700", 0.0), minority * 100, minority * net_assets,
        -bs[last].get("3700", 0.0) - minority * net_assets))
    ex = [l for l in o.nci_lines if l["entity"] == "ABSE" and l["period"] == (2024, 6)]
    print("attribution journal %s:" % (ex[0]["journal"] if ex else "-"), [(l["account"], round(l["amount"], 2)) for l in ex])
    for p in ((2024, 6), (2024, 12)):
        eq = [l for l in o.eq_lines if l["entity"] == "ABJV" and l["period"] == p]
        print("ABJV pickup %d-%02d (%.0f%% of its result, %s):" % (p[0], p[1], o.resolve("ABJV", p)["eff"] * 100, o.resolve("ABJV", p)["source"]),
              [(l["account"], round(l["amount"], 2)) for l in eq])
    print("ABPT pickup in the Closing period 2023-13:", [l for l in o.eq_lines if l["entity"] == "ABPT" and l["period"] == (2023, 13)] or "none (close rows excluded)")
    print("\nacquisition:", {k: round(v, 2) for k, v in o.acq_result.items()})
    print("disposal:", {k: round(v, 2) for k, v in o.dsp_result.items()},
          "gain(+)/loss(-) %.2f" % -sum(l["amount"] for l in o.dsp_lines if l["role"] == "gain_loss"))
    from collections import Counter
    print("IC reconciliation statuses:", dict(Counter(r["status"] for r in o.recon)))
    print("IC difference posted to %s by period:" % o.policy["ic_difference_account"],
          {("%d-%02d" % l["period"]): round(v, 2) for l, v in sorted(((l, sum(x["amount"] for x in o.elims if x["period"] == l["period"] and x["account"] == o.policy["ic_difference_account"])) for l in o.elims), key=lambda t: t[0]["period"])[:0]} or "see expected.json")
    diff_by_p = defaultdict(float)
    for l in o.elims:
        if l["account"] == o.policy["ic_difference_account"]:
            diff_by_p[l["period"]] += l["amount"]
    print("  ", {"%d-%02d" % p: round(v, 2) for p, v in sorted(diff_by_p.items())})


if __name__ == "__main__":
    main()
