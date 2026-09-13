"""Expected intercompany results for fixtures/ic_decisions.sql (konsol#159,
konsolidat#175 review rounds 2 and 3).

check(ch) returns a list of mismatches; [] means the fixture produced exactly
these reconciliation rows and elimination entries. ch(sql) returns the query's
text. Kept free of pytest so the same check runs against a live stack.

The one fx pair depends on the EUR->USD average rate the warehouse holds (R):
ZZD's 925 EUR is 925 * R in USD. Everything else is USD.
"""

G = "consolidation_group = 'ZZGRP' AND fiscal_year = 2095"

# The fixture's rows, for loading and removing it.
FIXTURE_ROWS = [
    ("epm_staging.entities", "data_area_id LIKE 'ZZ%'"),
    ("epm_gold.consolidation_groups", "consolidation_group IN ('ZZGRP', 'ZZSUB')"),
    ("epm_staging.consolidation_ancestry", "consolidation_group IN ('ZZGRP', 'ZZSUB')"),
    ("epm_staging.ownership_periods", "consolidation_group IN ('ZZGRP', 'ZZSUB')"),
    ("epm_staging.historical_equity_rates", "consolidation_group IN ('ZZGRP', 'ZZSUB')"),
    ("epm_staging.group_exchange_rates", "fiscal_year = 2095"),
    ("epm_staging.intercompany_accounts", "description LIKE 'ZZ test%'"),
    ("epm_raw.trial_balance_submissions", "fiscal_year = 2095"),
    ("epm_raw.trial_balance_submission_control", "fiscal_year = 2095"),
]


def _fx(r):
    return 925 * r


# (period, pair, pair_event, balance_a, balance_b, matched, difference, cause, match_status)
def reconciliation(r):
    return [
        # decision 12: 100%-owned ZZA against 80%-owned ZZB, matched at 100%
        (1, "ZZA/1100 <> ZZB/2010", "joined", 1000, -1000, 1000, 0, "none", "matched"),
        # third review M2: ZZA submits nothing in P3 but is still a member, so
        # ZZB's -50 shows as a booking difference; ZZA catches up in P4
        (3, "ZZA/1100 <> ZZB/2010", "", 1000, -1050, 1000, -50, "booking", "over_tolerance"),
        (4, "ZZA/1100 <> ZZB/2010", "", 1050, -1050, 1050, 0, "none", "matched"),
        # third review L2: 70% against 80%, balance sheet and P&L
        (1, "ZZ7/1100 <> ZZB/2010", "joined", 600, -600, 600, 0, "none", "matched"),
        (1, "ZZ7/4030 <> ZZB/5030", "", -200, 200, 200, 0, "none", "matched"),
        # decision 14: a balance-sheet timing pair, open at P1, matched at P2
        (1, "ZZA/1100 <> ZZC/2010", "joined", 500, 0, 0, 500, "booking", "over_tolerance"),
        (2, "ZZA/1100 <> ZZC/2010", "", 500, -500, 500, 0, "none", "matched"),
        # ZZE joins in P3 (with ZZA quiet); ZZA's receivable booked before then
        # counts, ZZE's own pre-acquisition payable is not in the warehouse
        (3, "ZZA/1100 <> ZZE/2010", "joined", 200, 0, 0, 200, "booking", "over_tolerance"),
        (4, "ZZA/1100 <> ZZE/2010", "", 0, 200, 0, 200, "booking", "over_tolerance"),
        # leaving after P2, each reversed in P3: ZZH disposed of; third review
        # M1: ZZQ's stake moved to equity, and ZZSUB (holding ZZS, whose own
        # ownership period stays open) sold
        (1, "ZZA/1100 <> ZZH/2010", "joined", 400, -400, 400, 0, "none", "matched"),
        (3, "ZZA/1100 <> ZZH/2010", "left", 0, 0, 0, 0, "none", "matched"),
        (1, "ZZA/1100 <> ZZQ/2010", "joined", 150, -150, 150, 0, "none", "matched"),
        (3, "ZZA/1100 <> ZZQ/2010", "left", 0, 0, 0, 0, "none", "matched"),
        (1, "ZZA/1100 <> ZZS/2010", "joined", 300, -300, 300, 0, "none", "matched"),
        (3, "ZZA/1100 <> ZZS/2010", "left", 0, 0, 0, 0, "none", "matched"),
        # decisions 13 and 14: a P&L booking difference, then matched on the movement
        (1, "ZZA/4030 <> ZZB/5030", "", -300, 312, 300, 12, "booking", "over_tolerance"),
        (2, "ZZA/4030 <> ZZB/5030", "", -100, 100, 100, 0, "none", "matched"),
        # decision 13: across currencies, fx; never over tolerance
        (1, "ZZA/4030 <> ZZD/5030", "", -1000, _fx(r), _fx(r), _fx(r) - 1000, "fx", "fx_difference"),
    ]


# (period, view, kind, debit_account, debit_entity, credit_account, credit_entity) -> amount,
# summed over the entries with that key
def eliminations(r):
    return {
        # P1. ZZA 100% / ZZB 80%, 1000: 800 matched, 200 to NCI (ZZB's minority), 200 in the NCI view
        (1, "group", "matched", "1100", "ZZA", "2010", "ZZB"): 800,
        (1, "group", "nci", "1100", "ZZA", "NCI", "ZZB"): 200,
        # ZZ7 70% / ZZB 80%, 600: 420 matched; ZZB's extra 10% (60) to NCI as ZZ7's
        # minority's (the n_b branch); the NCI view takes 30% of ZZ7 (180) and 20% of ZZB (120)
        (1, "group", "matched", "1100", "ZZ7", "2010", "ZZB"): 420,
        (1, "group", "nci", "NCI", "ZZ7", "2010", "ZZB"): 60,
        (1, "nci", "matched", "1100", "ZZ7", "NCI", "ZZ7"): 180,
        # ... 200 of it is the ZZA pair's, 120 the ZZ7 pair's
        (1, "nci", "matched", "NCI", "ZZB", "2010", "ZZB"): 320,
        # the same on P&L, 200: 140 matched, 20 to NCI, 60 and 40 in the NCI view
        (1, "group", "matched", "5030", "ZZB", "4030", "ZZ7"): 140,
        (1, "group", "nci", "5030", "ZZB", "NCI", "ZZ7"): 20,
        (1, "nci", "matched", "NCI", "ZZ7", "4030", "ZZ7"): 60,
        # ... 60 of it is the ZZA P&L pair's (below), 40 the ZZ7 one's
        (1, "nci", "matched", "5030", "ZZB", "NCI", "ZZB"): 100,
        (1, "group", "difference", "1100", "ZZA", "2100", "ZZC"): 500,
        (1, "group", "matched", "1100", "ZZA", "2010", "ZZH"): 400,
        (1, "group", "matched", "1100", "ZZA", "2010", "ZZQ"): 150,
        (1, "group", "matched", "1100", "ZZA", "2010", "ZZS"): 300,
        (1, "group", "matched", "5030", "ZZB", "4030", "ZZA"): 240,
        (1, "group", "nci", "NCI", "ZZB", "4030", "ZZA"): 60,
        (1, "group", "difference", "5030", "ZZB", "2100", "ZZA"): 9.6,
        (1, "nci", "difference", "5030", "ZZB", "2100", "ZZB"): 2.4,
        (1, "group", "matched", "5030", "ZZD", "4030", "ZZA"): _fx(r),
        (1, "group", "difference", "2100", "ZZD", "4030", "ZZA"): 1000 - _fx(r),
        # P2
        (2, "group", "matched", "1100", "ZZA", "2010", "ZZC"): 500,
        (2, "group", "difference", "2100", "ZZC", "1100", "ZZA"): 500,
        (2, "group", "matched", "5030", "ZZB", "4030", "ZZA"): 80,
        (2, "group", "nci", "NCI", "ZZB", "4030", "ZZA"): 20,
        (2, "nci", "matched", "5030", "ZZB", "NCI", "ZZB"): 20,
        # P3. ZZB's 50 booking difference on the 80% side: 40 group view, 10 NCI view
        (3, "group", "difference", "2100", "ZZA", "2010", "ZZB"): 40,
        (3, "nci", "difference", "2100", "ZZB", "2010", "ZZB"): 10,
        (3, "group", "difference", "1100", "ZZA", "2100", "ZZE"): 200,
        # the three pairs that left, reversed
        (3, "group", "matched", "2010", "ZZH", "1100", "ZZA"): 400,
        (3, "group", "matched", "2010", "ZZQ", "1100", "ZZA"): 150,
        (3, "group", "matched", "2010", "ZZS", "1100", "ZZA"): 300,
        # P4. ZZA catches up: the difference reversed, 50 more matched (40, 10 to NCI, 10 NCI view)
        (4, "group", "difference", "2010", "ZZB", "2100", "ZZA"): 40,
        (4, "nci", "difference", "2010", "ZZB", "2100", "ZZB"): 10,
        (4, "group", "matched", "1100", "ZZA", "2010", "ZZB"): 40,
        (4, "group", "nci", "1100", "ZZA", "NCI", "ZZB"): 10,
        (4, "nci", "matched", "NCI", "ZZB", "2010", "ZZB"): 10,
        (4, "group", "difference", "2010", "ZZE", "2100", "ZZA"): 200,
        (4, "group", "difference", "2100", "ZZE", "1100", "ZZA"): 200,
    }


# The report's 100% view (group view + nci_amount + the NCI view's
# eliminations), to date at P4. The P&L pairs and the NCI line are clear;
# 1100/2010 hold the balances with ZZH, ZZQ and ZZS after they left (ZZA's now
# external receivables, and their own history, which the disposal gap leaves
# in the warehouse).
def full_view_to_date(r):
    return {"1100": 850, "2010": -850, "4030": 0, "5030": 0, "NCI": 0, "2100": 212 - (1000 - _fx(r))}


def _rows(ch, sql):
    text = ch(sql + " FORMAT TSV")
    return [line.split("\t") for line in text.splitlines() if line]


def _close(a, b):
    return abs(float(a) - float(b)) <= 0.01


def check(ch):
    problems = []
    rate = _rows(ch, "SELECT any(translation_rate) FROM epm_gold.gold_consolidated_trial_balance "
                     f"WHERE {G} AND data_area_id = 'ZZD' AND main_account = '5030'")
    r = float(rate[0][0]) if rate and rate[0][0] not in ("", "\\N") else 1.0

    got = {(int(p), pair): rest for p, pair, *rest in _rows(
        ch, "SELECT fiscal_period, concat(entity_a, '/', account_a, ' <> ', entity_b, '/', account_b), pair_event, "
            "balance_a, balance_b, matched_amount, difference, difference_cause, match_status "
            f"FROM epm_gold.gold_ic_reconciliation WHERE {G}")}
    want = {(p, pair): rest for p, pair, *rest in reconciliation(r)}
    for key in sorted(set(got) | set(want)):
        if key not in got or key not in want:
            problems.append(f"reconciliation {key}: {'missing' if key not in got else 'unexpected'}")
            continue
        g, w = got[key], want[key]
        if g[0] != w[0] or g[5] != w[5] or g[6] != w[6] or not all(_close(a, b) for a, b in zip(g[1:5], w[1:5])):
            problems.append(f"reconciliation {key}: got {g}, want {w}")

    got_e = {}
    for p, view, kind, dr, dre, cr, cre, amount in _rows(
            ch, "SELECT fiscal_period, elimination_view, elimination_kind, debit_account, debit_entity, "
                "credit_account, credit_entity, elimination_amount "
                f"FROM epm_gold.gold_ic_eliminations WHERE {G} AND rule_type = 'balance'"):
        key = (int(p), view, kind, dr, dre, cr, cre)
        got_e[key] = got_e.get(key, 0) + float(amount)
    want_e = eliminations(r)
    for key in sorted(set(got_e) | set(want_e)):
        if key not in got_e or key not in want_e or not _close(got_e[key], want_e[key]):
            problems.append(f"elimination {key}: got {got_e.get(key)}, want {want_e.get(key)}")

    full = dict(_rows(
        ch, "SELECT main_account, sum(amount) FROM ("
            f" SELECT main_account, amount FROM epm_gold.gold_fully_consolidated_tb WHERE {G}"
            "   AND adjustment_type IN ('entity', 'ic_elimination', 'ic_elimination_nci')"
            f" UNION ALL SELECT main_account, ifNull(nci_amount, 0) FROM epm_gold.gold_consolidated_trial_balance WHERE {G}"
            f" UNION ALL SELECT debit_account, debit_elimination FROM epm_gold.gold_ic_eliminations WHERE {G} AND elimination_view = 'nci'"
            f" UNION ALL SELECT credit_account, credit_elimination FROM epm_gold.gold_ic_eliminations WHERE {G} AND elimination_view = 'nci'"
            ") WHERE main_account IN ('1100', '2010', '4030', '5030', '2100', 'NCI') GROUP BY main_account"))
    for account, amount in full_view_to_date(r).items():
        if not _close(full.get(account, 0), amount):
            problems.append(f"100% view {account}: got {full.get(account)}, want {amount}")
    return problems
