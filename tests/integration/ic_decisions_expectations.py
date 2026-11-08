"""Expected intercompany results for fixtures/ic_decisions.sql (konsol#159,
konsolidat#175 review rounds 2 and 3; rewritten for konsol#117 pair 2, K3b).

Decision 12 (eliminate at the share both sides hold, the rest to an NCI leg, a
second 'nci' view for the 100% column) is SUPERSEDED (Deepak Pai, 8 Nov 2026,
konsol#117; konsolidat#204 option (a)). Layer 1 carries a full-method subsidiary
at 100% and every intercompany elimination is posted IN FULL (IFRS 10.B86(c)),
whatever the holding: ZZB (80%) and ZZ7 (70%) are eliminated at 100%, there is
no NCI leg and no 'nci' view, and the minority is one line from nci_amount, not
part of the elimination. What this proves:
  - reconciliation rows (already at 100%): matched, residuals, decisions 13 (fx)
    and 14 (timing, reversal on leave);
  - every elimination entry is group view, kind matched/difference, at the FULL
    amount of each pair (a share anywhere would change a figure below);
  - the group view alone (entity + ic_elimination) is the 100% consolidation.

check(ch) returns a list of mismatches; [] means the fixture produced exactly
these reconciliation rows and elimination entries. ch(sql) returns the query's
text. Kept free of pytest so the same check runs against a live stack.

The one fx pair depends on the EUR->USD average rate the warehouse holds (R):
ZZD's 925 EUR is 925 * R in USD. Everything else is USD.
"""

G = "consolidation_group = 'ZZGRP' AND fiscal_year = 2095"

# The fixture's rows, for loading and removing it.
#
# konsolidat#227: every entry names this fixture's OWN rows explicitly. The
# entities line used to be data_area_id LIKE 'ZZ%', which also deleted ZZOP --
# the one company the first-build fixture creates, loaded into the same
# warehouse by ci_full_build.py:85 before this suite runs. The chart lines
# below must stay explicit for the same reason: ZZCOA also holds ZZ1000,
# ZZ3000, ZZ3100 and ZZ4000, which are not ours to remove.
FIXTURE_ENTITIES = ("ZZ7", "ZZA", "ZZB", "ZZC", "ZZD", "ZZE", "ZZH", "ZZQ", "ZZS")
FIXTURE_ACCOUNTS = ("ZZ1010", "ZZ1100", "ZZ2010", "ZZ2100", "ZZ3010", "ZZ4030", "ZZ5030")

_ENTITY_LIST = ", ".join(f"'{e}'" for e in FIXTURE_ENTITIES)
_ACCOUNT_LIST = ", ".join(f"'{a}'" for a in FIXTURE_ACCOUNTS)

FIXTURE_ROWS = [
    ("epm_staging.main_accounts", f"main_account IN ({_ACCOUNT_LIST})"),
    ("epm_staging.cash_flow_categories", f"main_account IN ({_ACCOUNT_LIST})"),
    ("epm_staging.fiscal_periods", "fiscal_year = 2095"),
    ("epm_staging.entities", f"data_area_id IN ({_ENTITY_LIST})"),
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
        # 100%-owned ZZA against 80%-owned ZZB, matched at 100% (and eliminated in full)
        (1, "ZZA/ZZ1100 <> ZZB/ZZ2010", "joined", 1000, -1000, 1000, 0, "none", "matched"),
        # third review M2: ZZA submits nothing in P3 but is still a member, so
        # ZZB's -50 shows as a booking difference; ZZA catches up in P4
        (3, "ZZA/ZZ1100 <> ZZB/ZZ2010", "", 1000, -1050, 1000, -50, "booking", "over_tolerance"),
        (4, "ZZA/ZZ1100 <> ZZB/ZZ2010", "", 1050, -1050, 1050, 0, "none", "matched"),
        # third review L2: 70% against 80%, balance sheet and P&L
        (1, "ZZ7/ZZ1100 <> ZZB/ZZ2010", "joined", 600, -600, 600, 0, "none", "matched"),
        (1, "ZZ7/ZZ4030 <> ZZB/ZZ5030", "", -200, 200, 200, 0, "none", "matched"),
        # decision 14: a balance-sheet timing pair, open at P1, matched at P2
        (1, "ZZA/ZZ1100 <> ZZC/ZZ2010", "joined", 500, 0, 0, 500, "booking", "over_tolerance"),
        (2, "ZZA/ZZ1100 <> ZZC/ZZ2010", "", 500, -500, 500, 0, "none", "matched"),
        # ZZE joins in P3 (with ZZA quiet); ZZA's receivable booked before then
        # counts, ZZE's own pre-acquisition payable is not in the warehouse
        (3, "ZZA/ZZ1100 <> ZZE/ZZ2010", "joined", 200, 0, 0, 200, "booking", "over_tolerance"),
        (4, "ZZA/ZZ1100 <> ZZE/ZZ2010", "", 0, 200, 0, 200, "booking", "over_tolerance"),
        # leaving after P2, each reversed in P3: ZZH disposed of; third review
        # M1: ZZQ's stake moved to equity, and ZZSUB (holding ZZS, whose own
        # ownership period stays open) sold
        (1, "ZZA/ZZ1100 <> ZZH/ZZ2010", "joined", 400, -400, 400, 0, "none", "matched"),
        (3, "ZZA/ZZ1100 <> ZZH/ZZ2010", "left", 0, 0, 0, 0, "none", "matched"),
        (1, "ZZA/ZZ1100 <> ZZQ/ZZ2010", "joined", 150, -150, 150, 0, "none", "matched"),
        (3, "ZZA/ZZ1100 <> ZZQ/ZZ2010", "left", 0, 0, 0, 0, "none", "matched"),
        (1, "ZZA/ZZ1100 <> ZZS/ZZ2010", "joined", 300, -300, 300, 0, "none", "matched"),
        (3, "ZZA/ZZ1100 <> ZZS/ZZ2010", "left", 0, 0, 0, 0, "none", "matched"),
        # decisions 13 and 14: a P&L booking difference, then matched on the movement
        (1, "ZZA/ZZ4030 <> ZZB/ZZ5030", "", -300, 312, 300, 12, "booking", "over_tolerance"),
        (2, "ZZA/ZZ4030 <> ZZB/ZZ5030", "", -100, 100, 100, 0, "none", "matched"),
        # decision 13: across currencies, fx; never over tolerance
        (1, "ZZA/ZZ4030 <> ZZD/ZZ5030", "", -1000, _fx(r), _fx(r), _fx(r) - 1000, "fx", "fx_difference"),
    ]


# (period, view, kind, debit_account, debit_entity, credit_account, credit_entity) -> amount,
# summed over the entries with that key
def eliminations(r):
    return {
        # P1. ZZA 100% / ZZB 80%, 1000: eliminated in full, nothing to NCI
        (1, "group", "matched", "ZZ1100", "ZZA", "ZZ2010", "ZZB"): 1000,
        # ZZ7 70% / ZZB 80%, 600: in full (was 420 at the share, 60 NCI leg, 180/120 NCI view)
        (1, "group", "matched", "ZZ1100", "ZZ7", "ZZ2010", "ZZB"): 600,
        # the same on P&L, 200, in full (was 140 + 20 + NCI view 60/40)
        (1, "group", "matched", "ZZ5030", "ZZB", "ZZ4030", "ZZ7"): 200,
        (1, "group", "difference", "ZZ1100", "ZZA", "ZZ2100", "ZZC"): 500,
        (1, "group", "matched", "ZZ1100", "ZZA", "ZZ2010", "ZZH"): 400,
        (1, "group", "matched", "ZZ1100", "ZZA", "ZZ2010", "ZZQ"): 150,
        (1, "group", "matched", "ZZ1100", "ZZA", "ZZ2010", "ZZS"): 300,
        # ZZA -300 / ZZB +312: 300 matched in full (was 240 + 60 NCI); ZZB's whole
        # residual of 12 is the difference (was 9.6 group + 2.4 NCI view)
        (1, "group", "matched", "ZZ5030", "ZZB", "ZZ4030", "ZZA"): 300,
        (1, "group", "difference", "ZZ5030", "ZZB", "ZZ2100", "ZZA"): 12,
        (1, "group", "matched", "ZZ5030", "ZZD", "ZZ4030", "ZZA"): _fx(r),
        (1, "group", "difference", "ZZ2100", "ZZD", "ZZ4030", "ZZA"): 1000 - _fx(r),
        # P2
        (2, "group", "matched", "ZZ1100", "ZZA", "ZZ2010", "ZZC"): 500,
        (2, "group", "difference", "ZZ2100", "ZZC", "ZZ1100", "ZZA"): 500,
        # the P&L pair matched on the movement, 100 in full (was 80 + 20 NCI)
        (2, "group", "matched", "ZZ5030", "ZZB", "ZZ4030", "ZZA"): 100,
        # P3. ZZB's 50 booking difference on the 80% side: all 50 (was 40 group, 10 NCI view)
        (3, "group", "difference", "ZZ2100", "ZZA", "ZZ2010", "ZZB"): 50,
        (3, "group", "difference", "ZZ1100", "ZZA", "ZZ2100", "ZZE"): 200,
        # the three pairs that left, reversed
        (3, "group", "matched", "ZZ2010", "ZZH", "ZZ1100", "ZZA"): 400,
        (3, "group", "matched", "ZZ2010", "ZZQ", "ZZ1100", "ZZA"): 150,
        (3, "group", "matched", "ZZ2010", "ZZS", "ZZ1100", "ZZA"): 300,
        # P4. ZZA catches up: the difference reversed (50), 50 more matched, both in full
        (4, "group", "difference", "ZZ2010", "ZZB", "ZZ2100", "ZZA"): 50,
        (4, "group", "matched", "ZZ1100", "ZZA", "ZZ2010", "ZZB"): 50,
        (4, "group", "difference", "ZZ2010", "ZZE", "ZZ2100", "ZZA"): 200,
        (4, "group", "difference", "ZZ2100", "ZZE", "ZZ1100", "ZZA"): 200,
    }


# The group view alone (entity + ic_elimination rows of gold_fully_consolidated_tb)
# is the 100% consolidation, to date at P4: no nci_amount and no NCI-view legs are
# added back. Layer 1 holds ZZB and ZZ7 at 100% and the eliminations take the
# whole of each pair, so the P&L pairs and the NCI account are clear (an
# elimination posted at a share would leave a remainder on ZZ1100/ZZ2010/ZZ5030
# and fail here);
# ZZ1100/ZZ2010 hold the balances with ZZH, ZZQ and ZZS after they left (ZZA's now
# external receivables, and their own history, which the disposal gap leaves
# in the warehouse).
def full_view_to_date(r):
    return {"ZZ1100": 850, "ZZ2010": -850, "ZZ4030": 0, "ZZ5030": 0, "NCI": 0, "ZZ2100": 212 - (1000 - _fx(r))}


def _rows(ch, sql):
    text = ch(sql + " FORMAT TSV")
    return [line.split("\t") for line in text.splitlines() if line]


def _close(a, b):
    return abs(float(a) - float(b)) <= 0.01


def check(ch):
    problems = []
    rate = _rows(ch, "SELECT any(translation_rate) FROM epm_gold.gold_consolidated_trial_balance "
                     f"WHERE {G} AND data_area_id = 'ZZD' AND main_account = 'ZZ5030'")
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
            "   AND adjustment_type IN ('entity', 'ic_elimination')"
            ") WHERE main_account IN ('ZZ1100', 'ZZ2010', 'ZZ4030', 'ZZ5030', 'ZZ2100', 'NCI') GROUP BY main_account"))
    for account, amount in full_view_to_date(r).items():
        if not _close(full.get(account, 0), amount):
            problems.append(f"group view (100%) {account}: got {full.get(account)}, want {amount}")
    return problems
