#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = ["openpyxl>=3.1"]
# ///
"""Load a filled onboarding workbook (and its trial-balance files) into a konsol site.

    uv run konsol_load.py Aquila_Group_Master_Data.xlsx --tb-dir tb -s mysite
    uv run konsol_load.py workbook.xlsx --dry-run               # show what would be sent, call nothing
    uv run konsol_load.py workbook.xlsx --only Main_Accounts    # one sheet
    uv run konsol_load.py workbook.xlsx --skip FX_Rates --tb-dir tb

Everything goes through `frappectl` (https://github.com/grynn-in/frappectl): `frappectl doc
create|update|submit|list`, `frappectl file upload` and `frappectl method call`. Configure a
profile first (`frappectl auth login`) for a user with the EPM Admin (Close Lead) role; pass it
with -s. konsol-cli is not used: it moves the semantic model (dimensions, measures, datasets,
connectors) as a GitOps bundle and has no commands for entities, charts, groups or trial balances.

The loader is idempotent in the way a person would be: a row whose natural key already exists on
the site is updated (never recreated); a submittable row (ownership, FX rate, historical rate,
consolidation journal, business combination, business disposal) that already has a live document is
left alone; a trial-balance entity-period that is already submitted is reported by konsol and skipped.
Sheets load in dependency order (konsol_template.LOAD_ORDER); within a tree sheet, parents load before
children. A child-table sheet (Fiscal_Periods, CJ_Lines, BC_*, BD_Proceeds) is never loaded on its own:
its rows are nested into the parent document (konsol_template.CHILD_SHEETS).

Approval: a doctype konsol installs a Workflow on (Sheet.workflow: Consolidation Journal, Business
Combination, Business Disposal) refuses a plain `doc submit` while Draft, so the loader walks the
workflow: `frappe.model.workflow.apply_workflow` (Send for Approval), then
`konsol.close.approval_api.approve` with a reason (the self-approval rule). The others are submitted.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from collections import OrderedDict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from konsol_template import APPROVAL_DOCTYPES, CLOSE_SETTINGS_KEYS, BY_NAME, CHILD_SHEETS, LOAD_ORDER, Sheet, link_column  # noqa: E402


class Failed(Exception):
    pass


#: The reason recorded on every workflow approval the loader performs (konsol's approve
#: requires one when the approver also prepared the document).
APPROVAL_REASON = "Onboarding load"


# ---------------------------------------------------------------------------
# frappectl
# ---------------------------------------------------------------------------
class Frappectl:
    def __init__(self, profile=None, dry_run=False, verbose=False):
        self.profile, self.dry_run, self.verbose = profile, dry_run, verbose
        self.calls = 0

    def _run(self, args, stdin=None, read_only=False):
        cmd = ["frappectl", "--json"] + (["-s", self.profile] if self.profile else []) + args
        if self.verbose or (self.dry_run and not read_only):
            print("    $ " + " ".join(_quote(a) for a in cmd) + (" <<< %s" % _short(stdin) if stdin else ""))
        if self.dry_run and not read_only:
            return None
        self.calls += 1
        proc = subprocess.run(cmd, input=stdin, capture_output=True, text=True)
        if proc.returncode != 0:
            raise Failed((proc.stderr or proc.stdout).strip() or "frappectl exited %d" % proc.returncode)
        out = proc.stdout.strip()
        if not out:
            return None
        try:
            return json.loads(out)
        except json.JSONDecodeError:
            return out

    def list(self, doctype, filters, fields=("name",), limit=20):
        """Documents matching an equality filter dict. A None value means 'is not set'."""
        args = ["doc", "list", doctype, "--fields", ",".join(fields), "--limit", str(limit)]
        # always JSON: frappectl's `-f k=v` parser splits on any operator inside a value, so a free-text key such
        # as a journal description containing ">= 50%" or " like " would become a different filter
        # a ("like", pattern) value is a prefix match; anything else is equality
        fj = [[k, v[0], v[1]] if isinstance(v, tuple) else [k, "=", v] if v is not None else [k, "is", "not set"]
              for k, v in filters.items()]
        args += ["--filters-json", json.dumps(fj)]
        if self.dry_run:
            return []
        out = self._run(args, read_only=True)
        if isinstance(out, dict):
            out = out.get("data") or out.get("message") or []
        return out or []

    def get(self, doctype, name):
        """One document, children included. None in a dry run (nothing is read)."""
        if self.dry_run:
            return None
        return self._run(["doc", "get", doctype, name], read_only=True)

    def create(self, doctype, doc):
        out = self._run(["doc", "create", doctype], stdin=json.dumps(doc))
        return (out or {}).get("name") if isinstance(out, dict) else out

    def update(self, doctype, name, doc):
        return self._run(["doc", "update", doctype, name, "--force"], stdin=json.dumps(doc))

    def submit(self, doctype, name):
        return self._run(["doc", "submit", doctype, name])

    def upload(self, path):
        out = self._run(["file", "upload", path, "--private"])
        return (out or {}).get("file_url") if isinstance(out, dict) else None

    def call(self, method, _verb=None, **params):
        """Invoke a whitelisted method. frappectl POSTs by default; a method whitelisted for GET only
        (konsol.tb_bulk.get_upload) answers a POST with "Not permitted", so pass _verb="GET" for those."""
        args = ["method", "call", method] + (["-X", _verb] if _verb else [])
        for k, v in params.items():
            args += ["-f", "%s=%s" % (k, v)]
        out = self._run(args)
        if isinstance(out, dict) and "message" in out and len(out) == 1:
            return out["message"]
        return out


def _quote(a):
    return "'%s'" % a if (" " in a or '"' in a) else a


def _short(s, n=160):
    return s if len(s) <= n else s[:n] + "…"


# ---------------------------------------------------------------------------
# the workbook
# ---------------------------------------------------------------------------
def read_sheet(wb, sheet: Sheet):
    if sheet.name not in wb.sheetnames:
        return []
    ws = wb[sheet.name]
    rows = list(ws.iter_rows(values_only=True))
    if not rows:
        return []
    header = [str(h).strip() if h is not None else "" for h in rows[0]]
    kinds = {c.name: c for c in sheet.cols}
    out = []
    for i, raw in enumerate(rows[1:], start=2):
        if not any(v not in (None, "") for v in raw):
            continue
        row = {}
        for h, v in zip(header, raw):
            if not h:
                continue
            col = kinds.get(h)
            try:
                row[h] = _coerce(v, col)
            except ValueError as e:
                # a cell that is not what its column declares stops the run before anything is sent
                raise Failed("%s row %d, %s" % (sheet.name, i, e))
        out.append(row)
    return out


def _coerce(v, col):
    if v is None:
        return ""
    if hasattr(v, "isoformat"):
        return v.isoformat()[:10]
    if col is None:
        return v if not isinstance(v, str) else v.strip()
    if col.kind == "check":
        return 1 if str(v).strip().lower() in ("1", "1.0", "true", "yes", "x") else 0
    if col.kind in ("int", "float"):
        if isinstance(v, str) and not v.strip():
            return ""
        try:
            return int(float(v)) if col.kind == "int" else float(v)
        except (TypeError, ValueError):
            raise ValueError("column %s: %r is not a number" % (col.name, v))
    if col.kind == "date":
        return str(v).strip()[:10]
    if isinstance(v, float) and v.is_integer():
        return str(int(v))
    return str(v).strip()


def tree_order(rows, key, parent_key, scope=None):
    """Parents before children; rows whose parent is not in the sheet come first. With `scope`, keys are
    (scope value, key): the same member code may root two hierarchies."""
    def k(r, col):
        v = r.get(col)
        return (r.get(scope), v) if scope else v
    # several rows may share a key (a member's tranches with different effective_from): every row is kept,
    # the parent lookup resolves to the first row of the parent's key
    by_key = {}
    for r in rows:
        by_key.setdefault(k(r, key), r)
    done, out = set(), []

    def visit(r, depth=0):
        if id(r) in done or depth > 60:
            return
        p = k(r, parent_key)
        if r.get(parent_key) and p in by_key and p != k(r, key):
            visit(by_key[p], depth + 1)
        done.add(id(r))
        out.append(r)

    for r in rows:
        visit(r)
    return out


def _key_value(v):
    """A natural-key value: blank is 'not set', but 0 (the Opening period) is a value."""
    return None if v in ("", None) else v


def doc_fields(sheet: Sheet, row):
    """The row as a document: loader-only columns removed, blanks dropped."""
    skip = {c.name for c in sheet.cols if c.loader}
    return {k: v for k, v in row.items() if k not in skip and v not in ("", None)}


# ---------------------------------------------------------------------------
# loaders
# ---------------------------------------------------------------------------
class Loader:
    def __init__(self, fc: Frappectl, allow_examples=False):
        self.fc = fc
        self.allow_examples = allow_examples
        self.counts = OrderedDict()
        self.failures = []
        self.cg_names = {}      # consolidation group code -> group node name
        self.member_names = {}  # (hierarchy, code) -> member name
        self.node_names = {}    # (group, entity or '') -> Consolidation Group node name
        self.sheet_nodes = {}   # (group, entity or '') -> parent_group code, from the workbook's Consolidation_Groups

    def note(self, sheet, what):
        self.counts.setdefault(sheet, OrderedDict())
        self.counts[sheet][what] = self.counts[sheet].get(what, 0) + 1

    def fail(self, sheet, label, err):
        self.failures.append((sheet, label, str(err)))
        self.note(sheet, "failed")
        print("    FAILED %s: %s" % (label, _short(str(err), 400)))

    def guard_examples(self, sheet, rows):
        bad = [r for r in rows if any(str(v).startswith("EXAMPLE_") for v in r.values())]
        if bad and not self.allow_examples:
            raise Failed("%s has %d EXAMPLE_ rows from the template; delete them (or pass --allow-examples)" % (sheet.name, len(bad)))

    def upsert(self, sheet, row, filters, doc, label, name=None):
        """Create or update by natural key. Returns the document name (None in dry run)."""
        try:
            existing = self.fc.list(sheet.doctype, filters)
            if existing:
                nm = existing[0]["name"]
                self.fc.update(sheet.doctype, nm, doc)
                self.note(sheet.name, "updated")
                return nm
            nm = self.fc.create(sheet.doctype, doc)
            self.note(sheet.name, "created")
            return nm or name
        except Failed as e:
            self.fail(sheet.name, label, e)
            return None

    def submit_once(self, sheet, filters, doc, label):
        """Create and approve unless a live (draft or submitted) document already has the key.

        Approval is a plain submit, or for a workflow doctype (sheet.workflow) the two
        workflow steps: Send for Approval, then konsol's approve with a reason."""
        try:
            existing = self.fc.list(sheet.doctype, filters, fields=("name", "docstatus"))
            if any(int(d.get("docstatus", 0)) == 1 for d in existing):
                self.note(sheet.name, "already live")
                return
            drafts = [d["name"] for d in existing if int(d.get("docstatus", 0)) == 0]
            if drafts:
                # a draft left by an earlier run (its approval was refused): approve it, do not create a twin
                nm, what = drafts[0], "approved existing draft"
            else:
                nm = self.fc.create(sheet.doctype, doc)
                if nm is None and self.fc.dry_run:
                    nm = "<%s>" % label   # so the dry run shows the approval calls too
                if nm is None:
                    raise Failed("doc create returned no name; nothing approved")
                what = "approved" if sheet.doctype in APPROVAL_DOCTYPES else "submitted"
            if nm:
                self.approve(sheet, nm)
            self.note(sheet.name, what)
        except Failed as e:
            self.fail(sheet.name, label, e)

    def approve(self, sheet, name):
        """Submit = approval. A doctype konsol judges by the self-approval policy (APPROVAL_DOCTYPES) is approved
        through konsol.close.approval_api.approve with a reason, after the workflow's Send for Approval when it has
        a workflow; anything else is a plain submit."""
        if sheet.workflow and self._workflow_state(sheet.doctype, name) in (None, "", "Draft"):
            # a draft left in Pending Approval by an earlier run must not be sent again: "Not a valid Workflow Action"
            self.fc.call("frappe.model.workflow.apply_workflow",
                         doc=json.dumps({"doctype": sheet.doctype, "name": name}), action="Send for Approval")
        if sheet.doctype in APPROVAL_DOCTYPES:
            self.fc.call("konsol.close.approval_api.approve", doctype=sheet.doctype, name=name, reason=APPROVAL_REASON)
        else:
            self.fc.submit(sheet.doctype, name)

    def _workflow_state(self, doctype, name):
        """The document's current workflow state: konsol's workflows drive the `status` field, a site's own may use
        `workflow_state`. Unknown (dry run, or not readable) counts as Draft."""
        if self.fc.dry_run:
            return "Draft"
        rows = self.fc.list(doctype, {"name": name}, fields=("name", "status", "workflow_state"))
        row = rows[0] if rows else {}
        return row.get("workflow_state") or row.get("status")

    # -- sheet handlers --------------------------------------------------------
    def load_settings(self, sheet, rows):
        values = {r["setting"]: r["value"] for r in rows if r.get("setting")}
        for single, doc in (("EPM Settings", {k: v for k, v in values.items() if k not in CLOSE_SETTINGS_KEYS}),
                            ("Close Settings", {k: v for k, v in values.items() if k in CLOSE_SETTINGS_KEYS})):
            if not doc:
                continue
            try:
                self.fc.update(single, single, doc)
                self.note(sheet.name, "updated %s" % single)
            except Failed as e:
                self.fail(sheet.name, single, e)

    def load_fiscal_years(self, sheet, rows, periods):
        years = {y.get("fiscal_year") for y in rows}
        blank = [p for p in periods if p.get("fiscal_year") in ("", None)]
        if blank:
            self.fail("Fiscal_Periods", "%d row(s)" % len(blank), "fiscal_year is empty (not loaded)")
        periods = [p for p in periods if p.get("fiscal_year") not in ("", None)]
        orphans = sorted({str(p.get("fiscal_year")) for p in periods if p.get("fiscal_year") not in years})
        if orphans:
            self.fail("Fiscal_Periods", "FY" + ", FY".join(orphans), "Fiscal_Periods rows without a Fiscal_Years row (not loaded)")
        for y in rows:
            if y.get("fiscal_year") in ("", None):
                self.fail(sheet.name, "(blank)", "fiscal_year is empty")
                continue
            fy = int(y["fiscal_year"])
            child = [doc_fields(BY_NAME["Fiscal_Periods"], p) for p in periods if int(p["fiscal_year"]) == fy]
            for c in child:
                c.pop("fiscal_year", None)
                c.setdefault("status", "Open")
            doc = doc_fields(sheet, y)
            doc["periods"] = child
            try:
                existing = self.fc.list(sheet.doctype, {"fiscal_year": fy})
                if existing:
                    self.note(sheet.name, "exists (periods left as declared)")
                    continue
                self.fc.create(sheet.doctype, doc)
                self.note(sheet.name, "created")
            except Failed as e:
                self.fail(sheet.name, "FY%d" % fy, e)

    def load_simple(self, sheet, rows):
        if sheet.tree:
            rows = tree_order(rows, sheet.key[0], sheet.tree)
        for r in rows:
            key = {k: _key_value(r.get(k)) for k in sheet.key}
            label = "/".join(str(v) for v in key.values() if v is not None)
            doc = doc_fields(sheet, r)
            if sheet.submit:
                self.submit_once(sheet, key, doc, label)
            else:
                self.upsert(sheet, r, key, doc, label)

    def load_hierarchies(self, sheet, rows):
        # a Published header needs at least one member, so a NEW hierarchy is created Draft and published by
        # publish_hierarchies() after the members; an existing Published one is never demoted
        for r in rows:
            doc = doc_fields(sheet, r)
            publish = doc.get("status") == "Published"
            try:
                existing = self.fc.list(sheet.doctype, {"hierarchy_name": r["hierarchy_name"]}, fields=("name", "status"))
            except Failed as e:
                self.fail(sheet.name, r["hierarchy_name"], e)
                continue
            live = existing[0].get("status") if existing else None
            if publish and live != "Published":
                doc["status"] = "Draft"
            r["_publish"] = publish and live != "Published"
            self.upsert(sheet, r, {"hierarchy_name": r["hierarchy_name"]}, doc, r["hierarchy_name"])

    def publish_hierarchies(self, headers):
        """Runs after Reporting_Hierarchy_Members whether or not that sheet loaded: a header declared Published
        is published, and a hierarchy without members is reported, not left Draft in silence."""
        for hd in headers:
            if hd.get("_publish"):
                try:
                    self.fc.update("Reporting Hierarchy", hd["hierarchy_name"], {"status": "Published"})
                    self.note("Reporting_Hierarchies", "published")
                except Failed as e:
                    self.fail("Reporting_Hierarchies", hd["hierarchy_name"], e)

    def load_members(self, sheet, rows, headers):
        rows = tree_order(rows, "member_code", "parent_member_code", scope="reporting_hierarchy")
        for r in rows:
            h, code = r["reporting_hierarchy"], r["member_code"]
            doc = doc_fields(sheet, r)
            parent_code = r.get("parent_member_code")
            if parent_code:
                pname = self.member_names.get((h, parent_code))
                if pname is None and not self.fc.dry_run:
                    found = self.fc.list(sheet.doctype, {"reporting_hierarchy": h, "member_code": parent_code})
                    pname = found[0]["name"] if found else None
                if pname is None and not self.fc.dry_run:
                    self.fail(sheet.name, "%s/%s" % (h, code), "parent member %s not found" % parent_code)
                    continue
                doc["parent_member"] = pname or "<%s>" % parent_code
            key = {"reporting_hierarchy": h, "member_code": code, "effective_from": _key_value(r.get("effective_from"))}
            nm = self.upsert(sheet, r, key, doc, "%s/%s" % (h, code))
            self.member_names[(h, code)] = nm

    def load_groups(self, sheet, rows):
        for r in rows:
            self.sheet_nodes[(r["consolidation_group"], r.get("data_area_id") or "")] = r.get("parent_group") or ""
        groups = [r for r in rows if r.get("is_group") or not r.get("data_area_id")]
        entities = [r for r in rows if r not in groups]
        groups = tree_order(groups, "consolidation_group", "parent_group")
        for r in groups + entities:
            doc = doc_fields(sheet, r)
            parent = r.get("parent_group")
            if parent:
                pname = self.cg_names.get(parent)
                if pname is None and not self.fc.dry_run:
                    found = self.fc.list(sheet.doctype, {"consolidation_group": parent, "data_area_id": None})
                    pname = found[0]["name"] if found else None
                if pname is None and not self.fc.dry_run:
                    self.fail(sheet.name, "%s/%s" % (r["consolidation_group"], r.get("data_area_id") or "group"),
                              "parent group node %s not found" % parent)
                    continue
                doc["parent_consolidation_group"] = pname or "<%s>" % parent
            key = {"consolidation_group": r["consolidation_group"], "data_area_id": r.get("data_area_id") or None}
            nm = self.upsert(sheet, r, key, doc, "%s/%s" % (r["consolidation_group"], r.get("data_area_id") or "group"))
            if not r.get("data_area_id"):
                self.cg_names[r["consolidation_group"]] = nm

    def find_node(self, group, entity=""):
        """Name of the Consolidation Group node (group, entity); blank entity = the group's own node. None if absent.
        In a dry run nothing is read from the site: the node is looked up in the workbook's own Consolidation_Groups
        rows (a placeholder name when they exist, None when they do not name it)."""
        k = (group, entity or "")
        if k not in self.node_names:
            if self.fc.dry_run:
                known = k in self.sheet_nodes or not self.sheet_nodes   # no Consolidation_Groups rows: cannot tell
                self.node_names[k] = "<%s/%s>" % k if known else None
            else:
                found = self.fc.list("Consolidation Group", {"consolidation_group": group, "data_area_id": entity or None})
                self.node_names[k] = found[0]["name"] if found else None
        return self.node_names[k]

    def tree_parent_node(self, group, entity=""):
        """Name of the tree parent of the node (group, entity): the node's parent_consolidation_group (the
        workbook's parent_group in a dry run). It is the group's own node only for a node directly under it."""
        if self.fc.dry_run:
            parent = self.sheet_nodes.get((group, entity or ""))
            return self.find_node(parent) if parent else None
        found = self.fc.list("Consolidation Group", {"consolidation_group": group, "data_area_id": entity or None},
                             fields=("name", "parent_consolidation_group"))
        return (found[0].get("parent_consolidation_group") or None) if found else None

    def load_ownership(self, sheet, rows):
        for r in rows:
            where = "%s/%s" % (r["consolidation_group"], r.get("data_area_id") or "group")
            owner = r.get("owner_entity")
            label = "%s%s/%s" % (where, " <- %s" % owner if owner else "", r["effective_date"])
            doc = doc_fields(sheet, r)
            key = {"consolidation_group": r["consolidation_group"], "data_area_id": r.get("data_area_id") or None,
                   "effective_date": r["effective_date"]}
            try:
                if owner:
                    node = self.find_node(r["consolidation_group"], owner)
                    if node is None:
                        raise Failed("owner_entity %s has no node in group %s (Consolidation_Groups)" % (owner, r["consolidation_group"]))
                else:
                    # a blank owner is the owned node's tree parent; always part of the key, so a blank row
                    # is never mistaken for a row of another holder
                    node = self.tree_parent_node(r["consolidation_group"], r.get("data_area_id") or "")
                    if node is None:
                        raise Failed("no owner_entity, and %s has no parent node in Consolidation_Groups to take as the owner" % where)
            except Failed as e:
                self.fail(sheet.name, label, e)
                continue
            doc["owner_node"] = key["owner_node"] = node
            self.submit_once(sheet, key, doc, label)

    def check_declarations(self, rows):
        """The server's refusals that can be known from the sheet, by name, before anything is sent."""
        for i, r in enumerate(rows, start=2):
            where = "Method_Declarations row %d (%s/%s)" % (i, r.get("consolidation_group"), r.get("data_area_id"))
            for col in ("consolidation_group", "data_area_id", "consolidation_method", "effective_date"):
                if not r.get(col):
                    raise Failed("%s: %s is empty" % (where, col))
            if not str(r.get("reason") or "").strip():
                raise Failed("%s: reason is required (the arrangement, the holders and the standard)" % where)
            if r["consolidation_method"] not in ("full", "proportional", "equity", "none"):
                raise Failed("%s: method %s is refused (full, proportional, equity or none)" % (where, r["consolidation_method"]))
            if r.get("end_date") and r["end_date"] < r["effective_date"]:
                raise Failed("%s: end_date %s is before effective_date %s" % (where, r["end_date"], r["effective_date"]))

    def load_declarations(self, sheet, rows):
        """Merge declarations into each group's own node (blank entity), by (data_area_id, effective_date): add the
        missing rows, leave matching ones alone, never delete. One update per group."""
        by_group = OrderedDict()
        for r in rows:
            by_group.setdefault(r["consolidation_group"], []).append(r)
        for group, grows in by_group.items():
            try:
                name = self.find_node(group)
                if name is None:
                    raise Failed("group %s has no node without an entity (Consolidation_Groups); a declaration sits on that node, not on an entity node" % group)
                node = self.fc.get(sheet.doctype, name) or {}
                if node.get("data_area_id"):
                    raise Failed("node %s carries entity %s; declare on the group's node without an entity" % (name, node["data_area_id"]))
                existing = list(node.get("method_declarations") or [])
                have = {(d.get("data_area_id"), str(d.get("effective_date") or "")[:10]) for d in existing}
                added = [doc_fields(sheet, r) for r in grows if (r["data_area_id"], r["effective_date"]) not in have]
                for a in added:
                    a.pop("consolidation_group", None)
                if added:
                    self.fc.update(sheet.doctype, name, {"method_declarations": existing + added})
                self.note(sheet.name, "added %d" % len(added) if added else "unchanged")
            except Failed as e:
                self.fail(sheet.name, group, e)

    def load_deals(self, sheet, rows, children_by_sheet):
        """A parent sheet with child-table sheets (Consolidation Journals, Business
        Combinations, Business Disposals): one approved document per parent row, with
        each child sheet's rows of the same link value (deal_ref, journal_ref: the
        loader-only column both sheets share) nested as the doctype's table field.
        The link column is never sent.

        children_by_sheet: {child Sheet: [rows]} for the sheets whose parent_sheet is
        this one. A child row naming a link no parent row carries is a failure (it
        would otherwise vanish silently)."""
        links = {child: link_column(sheet, child) for child in children_by_sheet}
        for child, crows in children_by_sheet.items():
            link = links[child]
            refs = {r.get(link) for r in rows}
            for c in crows:
                if c.get(link) not in refs:
                    self.fail(child.name, str(c.get(link) or "(blank %s)" % link),
                              "no %s row has this %s" % (sheet.name, link))
        for r in rows:
            doc = doc_fields(sheet, r)
            for child, crows in children_by_sheet.items():
                link = links[child]
                doc[child.table_field] = [doc_fields(child, c) for c in crows if c.get(link) == r.get(link)]
            key = {k: _key_value(r.get(k)) for k in sheet.key}
            if sheet.name == "Consolidation_Journals":
                # the server holds no journal_ref, so the reference is stored as a leading "[ref] " on the
                # description, and the journal is found by that prefix; the rest of the description is free text
                tag = "[%s] " % r["journal_ref"]
                doc["description"] = tag + doc["description"] if doc.get("description") else tag.strip()
                key.pop("journal_ref", None)
                key["description"] = ("like", tag.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_").rstrip() + "%")
            ref = next((r.get(l) for l in links.values() if r.get(l)), None)
            label = "%s (%s)" % (ref, "/".join(str(v) for v in key.values() if v is not None))
            self.submit_once(sheet, key, doc, label)

    # -- trial balances ---------------------------------------------------------
    def load_trial_balances(self, tb_dir, amount_basis, wait):
        files = sorted(f for f in os.listdir(tb_dir) if f.lower().endswith((".xlsx", ".csv")) and not f.startswith("~$"))
        if not files:
            print("  no .xlsx/.csv files in %s" % tb_dir)
            return
        for f in files:
            path = os.path.join(tb_dir, f)
            print("  %s" % f)
            try:
                url = self.fc.upload(path)
                params = {"file_url": url or "<file_url>"}
                if amount_basis:
                    params["amount_basis"] = amount_basis
                report = self.fc.call("konsol.tb_bulk.check_file", **params)
                if self.fc.dry_run:
                    self.fc.call("konsol.tb_bulk.load", name="<Trial Balance Upload>")
                    continue
                if not isinstance(report, dict):
                    raise Failed("check_file returned %r (an upload may have been created server-side)" % (report,))
                name = report.get("name")
                rows = (report.get("report") if isinstance(report, dict) else None) or []
                if isinstance(rows, str):
                    rows = json.loads(rows)
                # konsol.tb_bulk_model.check_group: one row per entity-period with ok, errors, warnings, existing
                ready = [x for x in rows if x.get("ok") is True]
                not_ready = [x for x in rows if x not in ready]
                warned = sum(1 for x in rows if x.get("warnings"))
                print("    upload %s: %d entity-periods, %d ready, %d not ready%s" % (
                    name, len(rows), len(ready), len(not_ready), ", %d with warnings" % warned if warned else ""))
                for x in not_ready[:8]:
                    reasons = list(x.get("errors") or [])
                    if x.get("existing"):
                        reasons.append("already submitted as %s" % x["existing"])
                    print("      - %s FY%s P%s: %s" % (x.get("entity"), x.get("fiscal_year"), x.get("fiscal_period"),
                                                       _short("; ".join(reasons) or "not ok", 220)))
                if len(not_ready) > 8:
                    print("      … %d more" % (len(not_ready) - 8))
                if not ready or not name:
                    self.note("Trial_Balance", "nothing loaded")
                    continue
                self._start_load(name)
                status = self._wait_upload(name, wait)
                print("    -> %s" % status)
                if status.startswith("Loaded"):
                    self.note("Trial_Balance", status)
                else:
                    # Failed, Partly Loaded, Cancelled, unknown or timed out: the run must not end green
                    self.fail("Trial_Balance", f, status)
            except Failed as e:
                self.fail("Trial_Balance", f, e)

    def _start_load(self, name):
        """konsol.tb_bulk.load answers 200 with `refused` when its re-check disagrees with check_file and
        leaves the upload at Checked; waiting for it would run to the timeout."""
        def once():
            out = self.fc.call("konsol.tb_bulk.load", name=name, skip_invalid=1)
            if isinstance(out, dict) and out.get("refused"):
                raise Failed("load refused: %s" % out["refused"])
            return out
        try:
            return once()
        except Failed as e:
            # the previous file's load job may still be committing its submissions; a deadlock (MariaDB 1213)
            # on the shared rows is transient, so try once more after a pause
            if "Deadlock" not in str(e):
                raise
            print("    deadlock on load, retrying once")
            time.sleep(10)
            return once()

    def _wait_upload(self, name, wait):
        deadline = time.time() + wait
        last, misses = "", 0
        while time.time() < deadline:
            try:
                st = self.fc.call("konsol.tb_bulk.get_upload", _verb="GET", name=name)
                misses = 0
            except Failed as e:
                # one failed poll is transient; three in a row are not
                misses += 1
                if misses >= 3:
                    return "status unknown after 3 failed polls (%s); check Trial Balance Upload %s" % (_short(str(e), 120), name)
                time.sleep(5)
                continue
            status = (st or {}).get("status_now") or (st or {}).get("status") or ""
            if status != last:
                last = status
            if status in ("Loaded", "Partly Loaded", "Failed", "Cancelled"):
                loaded = (st or {}).get("loaded_count")
                return "%s%s" % (status, " (%s loaded)" % loaded if loaded is not None else "")
            time.sleep(5)
        return "still loading after %ds (check Trial Balance Upload %s)" % (wait, name)


# ---------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("workbook", help="the filled onboarding workbook (.xlsx)")
    ap.add_argument("--tb-dir", help="folder of trial-balance files to load after the master data (one upload per file, in name order)")
    ap.add_argument("--tb-basis", default=None, help="Amount Basis for files whose rows do not carry amount_basis")
    ap.add_argument("-s", "--profile", help="frappectl profile (site)")
    ap.add_argument("--only", action="append", default=[], help="load only this sheet (repeatable); Trial_Balance for the files")
    ap.add_argument("--skip", action="append", default=[], help="skip this sheet (repeatable)")
    ap.add_argument("--dry-run", action="store_true", help="print the frappectl calls, send nothing")
    ap.add_argument("--allow-examples", action="store_true", help="load rows with EXAMPLE_ codes too")
    ap.add_argument("--wait", type=int, default=900, help="seconds to wait for each bulk load to finish")
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args()

    from openpyxl import load_workbook
    wb = load_workbook(args.workbook, data_only=True)
    fc = Frappectl(args.profile, args.dry_run, args.verbose)
    ld = Loader(fc, args.allow_examples)
    want = set(args.only) if args.only else set(LOAD_ORDER) | {"Trial_Balance"}
    want -= set(args.skip)

    try:
        data = {name: read_sheet(wb, BY_NAME[name]) for name in LOAD_ORDER}
        for name in LOAD_ORDER:
            if data[name]:
                ld.guard_examples(BY_NAME[name], data[name])
        ld.check_declarations(data["Method_Declarations"])
    except Failed as e:
        sys.exit("refused: %s" % e)

    for name in LOAD_ORDER:
        sheet = BY_NAME[name]
        # a parent sheet runs when any of its child sheets has rows, so orphan child rows are reported
        has_rows = data[name] or any(data[c.name] for c in CHILD_SHEETS.get(name, ()))
        if name not in want or not has_rows:
            continue
        print("%s -> %s (%d rows)" % (name, sheet.doctype, len(data[name])))
        if name == "Settings":
            ld.load_settings(sheet, data[name])
        elif name == "Fiscal_Years":
            ld.load_fiscal_years(sheet, data[name], data["Fiscal_Periods"])
        elif name == "Fiscal_Periods":
            continue  # loaded with their year
        elif name == "Reporting_Hierarchies":
            ld.load_hierarchies(sheet, data[name])
        elif name == "Reporting_Hierarchy_Members":
            ld.load_members(sheet, data[name], data["Reporting_Hierarchies"])
        elif name == "Consolidation_Groups":
            ld.load_groups(sheet, data[name])
        elif name == "Ownership_Periods":
            ld.load_ownership(sheet, data[name])
        elif name == "Method_Declarations":
            ld.load_declarations(sheet, data[name])
        elif sheet.parent_sheet:
            continue  # nested into its parent sheet's documents
        elif name in CHILD_SHEETS:
            ld.load_deals(sheet, data[name], {c: data[c.name] for c in CHILD_SHEETS[name]})
        else:
            ld.load_simple(sheet, data[name])

    if "Reporting_Hierarchies" in want:
        ld.publish_hierarchies(data["Reporting_Hierarchies"])

    if args.tb_dir and "Trial_Balance" in want:
        print("Trial_Balance -> Trial Balance Upload (%s)" % args.tb_dir)
        ld.load_trial_balances(args.tb_dir, args.tb_basis, args.wait)

    print("\nSummary%s:" % (" (dry run)" if args.dry_run else ""))
    for sheet, c in ld.counts.items():
        print("  %-28s %s" % (sheet, ", ".join("%s %d" % (k, v) for k, v in c.items())))
    if ld.failures:
        print("\n%d failure(s):" % len(ld.failures))
        for sheet, label, err in ld.failures:
            print("  %s %s: %s" % (sheet, label, _short(err, 300)))
        sys.exit(1)
    print("frappectl calls: %d" % fc.calls)


if __name__ == "__main__":
    main()
