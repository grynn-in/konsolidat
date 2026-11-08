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

    def test_proportional_stays_refused(self):
        site = FakeSite(groups())
        code, out = run_loader(site, {"Method_Declarations": [dict(DECL, consolidation_method="proportional")]})
        self.assertNotEqual(code, 0)
        self.assertEqual(site.writes, [])

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


if __name__ == "__main__":
    unittest.main()
