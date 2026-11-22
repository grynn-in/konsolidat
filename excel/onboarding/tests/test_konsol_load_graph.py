"""konsol#117 pair 2, K5a: the loader reads an Ownership Period's owner and the Method_Declarations sheet.

No live site: the one function every call goes through, Frappectl._run, is replaced by a fake site that
keeps documents in a dict. Each test builds a small workbook with openpyxl and runs the loader's main().
"""
import contextlib
import io
import json
import os
import sys
import tempfile
import unittest
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

import konsol_load  # noqa: E402
from konsol_template import BY_NAME  # noqa: E402
from openpyxl import Workbook  # noqa: E402


class FakeSite:
    """Documents by doctype; records every write."""

    def __init__(self, docs=None):
        self.docs = docs or {}      # doctype -> {name: doc}
        self.writes = []            # (verb, doctype, name, payload)
        self.calls = []             # (method, {param: value}) for every `method call`
        self.n = 0

    def run(self, args, stdin=None, read_only=False):
        verb, doctype = args[1], args[2]
        store = self.docs.setdefault(doctype, {})
        if verb == "list":
            fj = json.loads(args[args.index("--filters-json") + 1])
            out = []
            for name, d in store.items():
                if all((d.get(k) in (None, "")) if op == "is"
                       else str(d.get(k) or "").startswith(v.rstrip("%")) if op == "like" else d.get(k) == v
                       for k, op, v in fj):
                    out.append(dict(d, name=name))
            return out
        if verb == "get":
            return dict(store[args[3]], name=args[3])
        if verb == "create":
            doc = json.loads(stdin)
            self.n += 1
            name = "%s-%d" % (doctype[:3].upper(), self.n)
            store[name] = dict(doc, docstatus=0)
            self.writes.append(("create", doctype, name, doc))
            return {"name": name}
        if verb == "update":
            doc = json.loads(stdin)
            store[args[3]].update(doc)
            self.writes.append(("update", doctype, args[3], doc))
            return {"name": args[3]}
        if verb == "submit":
            store[args[3]]["docstatus"] = 1
            self.writes.append(("submit", doctype, args[3], None))
            return {}
        if args[0] == "method":
            self.calls.append((args[2], dict(a.split("=", 1) for a in args[3:] if "=" in a)))
            return {"message": {}}
        raise AssertionError("unexpected call %r" % (args,))


def workbook(sheets):
    wb = Workbook()
    wb.remove(wb.active)
    for name, rows in sheets.items():
        ws = wb.create_sheet(name)
        cols = BY_NAME[name].fieldnames
        ws.append(cols)
        for r in rows:
            ws.append([r.get(c) for c in cols])
    return wb


def run_loader(site, sheets, extra_args=()):
    wb = workbook(sheets)
    with tempfile.TemporaryDirectory() as d:
        path = os.path.join(d, "wb.xlsx")
        wb.save(path)
        out = io.StringIO()
        code = 0
        with mock.patch.object(konsol_load.Frappectl, "_run", lambda self, a, stdin=None, read_only=False: site.run(a, stdin, read_only)), \
                mock.patch.object(sys, "argv", ["konsol_load.py", path, *extra_args]), contextlib.redirect_stdout(out):
            try:
                konsol_load.main()
            except SystemExit as e:
                code = e.code if e.code is not None else 0
    return code, out.getvalue()


def node(group, entity="", parent=None):
    return {"consolidation_group": group, "data_area_id": entity or None, "docstatus": 0,
            "parent_consolidation_group": parent}


def groups():
    return {"Consolidation Group": {"CG-G": node("G"), "CG-A": node("G", "A", "CG-G"), "CG-B": node("G", "B", "CG-G"),
                                    "CG-J": node("G", "J", "CG-G")}}


GROUP_ROWS = [{"consolidation_group": "G", "is_group": 1},
              {"consolidation_group": "G", "data_area_id": "A", "parent_group": "G"},
              {"consolidation_group": "G", "data_area_id": "J", "parent_group": "G"}]


PERIOD = {"consolidation_group": "G", "data_area_id": "J", "effective_date": "2025-01-01",
          "ownership_pct": 30, "consolidation_method": "equity"}


class OwnerEntity(unittest.TestCase):
    def test_owner_entity_posts_the_resolved_owner_node(self):
        site = FakeSite(groups())
        code, out = run_loader(site, {"Ownership_Periods": [dict(PERIOD, owner_entity="A")]})
        creates = [w for w in site.writes if w[0] == "create" and w[1] == "Ownership Period"]
        self.assertEqual(len(creates), 1, out)
        self.assertEqual(creates[0][3]["owner_node"], "CG-A")
        self.assertNotIn("owner_entity", creates[0][3])

    def test_blank_owner_posts_the_tree_parent_node(self):
        site = FakeSite(groups())
        run_loader(site, {"Ownership_Periods": [dict(PERIOD)]})
        creates = [w for w in site.writes if w[0] == "create" and w[1] == "Ownership Period"]
        self.assertEqual(len(creates), 1)
        self.assertEqual(creates[0][3]["owner_node"], "CG-G")

    def test_blank_owner_row_is_not_swallowed_by_an_earlier_owner_row(self):
        site = FakeSite(groups())
        rows = [dict(PERIOD, owner_entity="A", ownership_pct=30), dict(PERIOD, ownership_pct=40)]
        code, out = run_loader(site, {"Ownership_Periods": rows})
        creates = [w for w in site.writes if w[0] == "create" and w[1] == "Ownership Period"]
        self.assertEqual(sorted((w[3]["owner_node"], w[3]["ownership_pct"]) for w in creates),
                         [("CG-A", 30), ("CG-G", 40)], out)

    def test_dry_run_names_an_owner_entity_with_no_node(self):
        site = FakeSite({})
        wb_rows = {"Consolidation_Groups": GROUP_ROWS,
                   "Ownership_Periods": [dict(PERIOD, owner_entity="NOPE")]}
        code, out = run_loader(site, wb_rows, extra_args=["--dry-run"])
        self.assertNotEqual(code, 0, out)
        self.assertIn("NOPE", out)

    def test_two_holders_of_one_entity_are_two_periods(self):
        site = FakeSite(groups())
        rows = [dict(PERIOD, owner_entity="A", ownership_pct=30), dict(PERIOD, owner_entity="B", ownership_pct=20)]
        code, out = run_loader(site, {"Ownership_Periods": rows})
        creates = [w for w in site.writes if w[0] == "create" and w[1] == "Ownership Period"]
        self.assertEqual(sorted(w[3]["owner_node"] for w in creates), ["CG-A", "CG-B"], out)
        # a second run finds both live and posts nothing
        before = len(site.writes)
        run_loader(site, {"Ownership_Periods": rows})
        self.assertEqual(len(site.writes), before)

    def test_unknown_owner_entity_is_named(self):
        site = FakeSite(groups())
        code, out = run_loader(site, {"Ownership_Periods": [dict(PERIOD, owner_entity="NOPE")]})
        self.assertEqual(code, 1)
        self.assertIn("NOPE", out)
        self.assertEqual([w for w in site.writes if w[1] == "Ownership Period"], [])


DECL = {"consolidation_group": "G", "data_area_id": "J", "consolidation_method": "equity",
        "effective_date": "2025-01-01", "end_date": "", "reason": "Joint control, IFRS 11.7"}


class MethodDeclarations(unittest.TestCase):
    def test_a_declaration_is_one_child_row_and_a_second_run_changes_nothing(self):
        site = FakeSite(groups())
        code, out = run_loader(site, {"Method_Declarations": [dict(DECL)]})
        self.assertEqual(code, 0, out)
        upd = [w for w in site.writes if w[0] == "update" and w[1] == "Consolidation Group"]
        self.assertEqual(len(upd), 1)
        self.assertEqual(upd[0][2], "CG-G")
        rows = upd[0][3]["method_declarations"]
        self.assertEqual(len(rows), 1)
        self.assertEqual((rows[0]["data_area_id"], rows[0]["consolidation_method"], rows[0]["effective_date"]),
                         ("J", "equity", "2025-01-01"))
        before = len(site.writes)
        code, out = run_loader(site, {"Method_Declarations": [dict(DECL)]})
        self.assertEqual(code, 0, out)
        self.assertEqual(len(site.writes), before)

    def test_existing_rows_are_kept_when_one_is_added(self):
        site = FakeSite(groups())
        run_loader(site, {"Method_Declarations": [dict(DECL)]})
        run_loader(site, {"Method_Declarations": [dict(DECL), dict(DECL, data_area_id="B", reason="Other")]})
        stored = site.docs["Consolidation Group"]["CG-G"]["method_declarations"]
        self.assertEqual(sorted(r["data_area_id"] for r in stored), ["B", "J"])

    def test_none_is_a_valid_method(self):
        site = FakeSite(groups())
        code, out = run_loader(site, {"Method_Declarations": [dict(DECL, consolidation_method="none")]})
        self.assertEqual(code, 0, out)
        stored = site.docs["Consolidation Group"]["CG-G"]["method_declarations"]
        self.assertEqual(stored[0]["consolidation_method"], "none")

    def test_proportional_is_accepted_since_pair_3(self):
        """konsol#117 pair 3: the warehouse computes proportional (IFRS 11.20), so the loader no
        longer refuses it; it reaches the server like the other three methods."""
        site = FakeSite(groups())
        code, out = run_loader(site, {"Method_Declarations": [dict(DECL, consolidation_method="proportional")]})
        self.assertEqual(code, 0, out)
        stored = site.docs["Consolidation Group"]["CG-G"]["method_declarations"]
        self.assertEqual(stored[0]["consolidation_method"], "proportional")

    def test_blank_reason_is_refused_before_anything_is_sent(self):
        site = FakeSite(groups())
        code, out = run_loader(site, {"Method_Declarations": [dict(DECL, reason="")]})
        self.assertNotEqual(code, 0)
        self.assertIn("reason", str(code) + out)
        self.assertIn("J", str(code) + out)
        self.assertEqual(site.writes, [])


JOURNAL = {"journal_ref": "CJ-1", "consolidation_group": "G", "adjustment_type": "topside", "fiscal_year": 2023,
           "fiscal_period": 12, "currency": "USD", "description": "Opening, 70 percent"}


class JournalKey(unittest.TestCase):
    def test_journals_differing_only_in_description_are_one_journal(self):
        site = FakeSite(groups())
        run_loader(site, {"Consolidation_Journals": [dict(JOURNAL)]})
        n = len([w for w in site.writes if w[0] == "create" and w[1] == "Consolidation Journal"])
        self.assertEqual(n, 1)
        before = len(site.writes)
        run_loader(site, {"Consolidation_Journals": [dict(JOURNAL, description="Opening, 100 percent")]})
        self.assertEqual(len(site.writes), before, "a reworded journal was created a second time")

    def test_two_references_in_one_period_are_two_journals(self):
        site = FakeSite(groups())
        run_loader(site, {"Consolidation_Journals": [dict(JOURNAL), dict(JOURNAL, journal_ref="CJ-2")]})
        n = len([w for w in site.writes if w[0] == "create" and w[1] == "Consolidation Journal"])
        self.assertEqual(n, 2)


BC = {"deal_ref": "ACQ-B-2025", "consolidation_group": "G", "acquired_entity": "B", "acquisition_date": "2025-02-01",
      "share_acquired_pct": 100, "consideration_currency": "EUR"}
BD = {"deal_ref": "DSP-B-2025", "consolidation_group": "G", "disposed_entity": "B", "disposal_date": "2025-12-30",
      "share_disposed_pct": 100, "retained_interest_pct": 0, "proceeds_currency": "EUR"}


def deal_creates(site, doctype):
    return [w for w in site.writes if w[0] == "create" and w[1] == doctype]


class DealCounterparty(unittest.TestCase):
    def test_acquirer_entity_posts_the_resolved_node(self):
        site = FakeSite(groups())
        code, out = run_loader(site, {"Business_Combinations": [dict(BC, acquirer_entity="A")]})
        creates = deal_creates(site, "Business Combination")
        self.assertEqual(len(creates), 1, out)
        self.assertEqual(creates[0][3]["acquirer_node"], "CG-A")
        self.assertNotIn("acquirer_entity", creates[0][3])

    def test_blank_acquirer_posts_none(self):
        site = FakeSite(groups())
        run_loader(site, {"Business_Combinations": [dict(BC)]})
        creates = deal_creates(site, "Business Combination")
        self.assertEqual(len(creates), 1)
        self.assertNotIn("acquirer_node", creates[0][3])

    def test_disposer_entity_posts_the_resolved_node(self):
        site = FakeSite(groups())
        code, out = run_loader(site, {"Business_Disposals": [dict(BD, disposer_entity="A")]})
        creates = deal_creates(site, "Business Disposal")
        self.assertEqual(len(creates), 1, out)
        self.assertEqual(creates[0][3]["disposer_node"], "CG-A")
        self.assertNotIn("disposer_entity", creates[0][3])

    def test_blank_disposer_posts_none(self):
        site = FakeSite(groups())
        run_loader(site, {"Business_Disposals": [dict(BD)]})
        creates = deal_creates(site, "Business Disposal")
        self.assertEqual(len(creates), 1)
        self.assertNotIn("disposer_node", creates[0][3])

    def test_unknown_acquirer_is_named_and_nothing_posted(self):
        site = FakeSite(groups())
        code, out = run_loader(site, {"Business_Combinations": [dict(BC, acquirer_entity="NOPE")]})
        self.assertEqual(code, 1)
        self.assertIn("NOPE", out)
        self.assertEqual([w for w in site.writes if w[1] == "Business Combination"], [])

    def test_unknown_disposer_is_named_and_nothing_posted(self):
        site = FakeSite(groups())
        code, out = run_loader(site, {"Business_Disposals": [dict(BD, disposer_entity="NOPE")]})
        self.assertEqual(code, 1)
        self.assertIn("NOPE", out)
        self.assertEqual([w for w in site.writes if w[1] == "Business Disposal"], [])


def fx(period, from_cur, rate_type, quote, per="1", year=2025, to="EUR", reason=""):
    return {"to_currency": to, "from_currency": from_cur, "fiscal_year": year, "fiscal_period": period,
            "rate_type": rate_type, "quote": quote, "quoted_per": per, "change_reason": reason}


FX_ROWS = [fx(1, "USD", "Closing", 0.92), fx(1, "USD", "Average", 0.91),
           fx(1, "INR", "Closing", 0.955, "100"), fx(1, "INR", "Average", 0.95, "100"),
           fx(2, "USD", "Closing", 0.93), fx(2, "USD", "Average", 0.925)]


def sheet_creates(site):
    return [w for w in site.writes if w[0] == "create" and w[1] == "Rate Sheet"]


class FxRatesLoadRateSheets(unittest.TestCase):
    """konsol#592 pair 1: FX_Rates loads Rate Sheets, one per period, not Group Exchange Rates."""

    def test_one_statutory_sheet_per_period_with_a_row_per_pair(self):
        site = FakeSite()
        code, out = run_loader(site, {"FX_Rates": [dict(r) for r in FX_ROWS]})
        self.assertEqual(code, 0, out)
        self.assertEqual([w for w in site.writes if w[1] == "Group Exchange Rate"], [])
        creates = sheet_creates(site)
        self.assertEqual(sorted((w[3]["fiscal_year"], w[3]["fiscal_period"]) for w in creates), [(2025, 1), (2025, 2)])
        p1 = next(w[3] for w in creates if w[3]["fiscal_period"] == 1)
        self.assertEqual(p1["rate_basis"], "Statutory")
        rows = {r["from_currency"]: r for r in p1["rates"]}
        self.assertEqual(sorted(rows), ["INR", "USD"])
        self.assertEqual((rows["INR"]["to_currency"], rows["INR"]["quoted_per"], rows["INR"]["average_quote"],
                          rows["INR"]["closing_quote"]), ("EUR", "100", 0.95, 0.955))
        self.assertEqual((rows["USD"]["average_quote"], rows["USD"]["closing_quote"]), (0.91, 0.92))

    def test_no_provenance_field_is_sent(self):
        """Source and the ERP quotes are set only under a server flag; a plain insert leaves them blank."""
        site = FakeSite()
        run_loader(site, {"FX_Rates": [dict(r) for r in FX_ROWS]})
        for w in sheet_creates(site):
            for banned in ("source_note", "copied_from", "supersedes", "amended_from", "status", "change_reason"):
                self.assertNotIn(banned, w[3])
            for r in w[3]["rates"]:
                for banned in ("source", "erp_average_quote", "erp_closing_quote", "legacy_documents", "rate"):
                    self.assertNotIn(banned, r)

    def test_each_sheet_is_sent_for_approval_then_approved(self):
        site = FakeSite()
        run_loader(site, {"FX_Rates": [dict(r) for r in FX_ROWS]})
        names = [n for n in site.docs["Rate Sheet"]]
        self.assertEqual(len(names), 2)
        wf = [p for m, p in site.calls if m == "frappe.model.workflow.apply_workflow"]
        ap = [p for m, p in site.calls if m == "konsol.close.approval_api.approve"]
        self.assertEqual(sorted(p["name"] for p in ap), sorted(names))
        self.assertEqual(len(wf), 2)
        self.assertTrue(all(p["doctype"] == "Rate Sheet" and p["reason"] for p in ap))
        self.assertEqual([w for w in site.writes if w[0] == "submit"], [])

    def test_a_second_run_finds_the_sheets_live_and_sends_nothing(self):
        site = FakeSite()
        run_loader(site, {"FX_Rates": [dict(r) for r in FX_ROWS]})
        for d in site.docs["Rate Sheet"].values():
            d["docstatus"] = 1
        before = (len(site.writes), len(site.calls))
        code, out = run_loader(site, {"FX_Rates": [dict(r) for r in FX_ROWS]})
        self.assertEqual(code, 0, out)
        self.assertEqual((len(site.writes), len(site.calls)), before)

    def test_a_pair_quoted_per_different_units_is_refused_by_name(self):
        site = FakeSite()
        rows = [fx(1, "INR", "Closing", 0.955, "100"), fx(1, "INR", "Average", 0.0095, "1")]
        code, out = run_loader(site, {"FX_Rates": rows})
        self.assertEqual(code, 1)
        self.assertIn("INR", out)
        self.assertEqual(sheet_creates(site), [])

    def test_two_different_quotes_for_one_key_are_refused(self):
        site = FakeSite()
        rows = [fx(1, "USD", "Closing", 0.92), fx(1, "USD", "Closing", 0.93)]
        code, out = run_loader(site, {"FX_Rates": rows})
        self.assertEqual(code, 1)
        self.assertIn("USD", out)
        self.assertEqual(sheet_creates(site), [])

    def test_a_reason_in_the_sheet_is_reported_not_silently_dropped(self):
        site = FakeSite()
        code, out = run_loader(site, {"FX_Rates": [fx(1, "USD", "Closing", 0.92, reason="treasury"),
                                                   fx(1, "USD", "Average", 0.91)]})
        self.assertEqual(code, 0, out)
        self.assertIn("change_reason", out)


if __name__ == "__main__":
    unittest.main()
