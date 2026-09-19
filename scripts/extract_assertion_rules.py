#!/usr/bin/env python3
"""Regenerate docs/design/rules.md from the singular tests.

Every assertion in dbt_project/tests/ already carries its reasoning in a
leading comment — 126 of 126 do, and 83 cite the issue that caused them. That
prose is the most expensive thing in this repository: each line is a rule
someone learned by shipping a wrong number. It is also invisible, one file
deep, to anyone who has not read the whole test directory.

This script lifts those headers into one document, grouped by subject, so the
rules can be read as a body of knowledge rather than found one at a time.

It is a projection, never a source. Edit the test, not the document, and run
this again:

    python3 scripts/extract_assertion_rules.py

Output is deterministic, so a stale document shows up as a diff in CI.
"""
from __future__ import annotations
import re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TESTS = ROOT / "dbt_project" / "tests"
OUT = ROOT / "docs" / "design" / "rules.md"

# Subject → the words that place an assertion in it. First match wins, so the
# order is the grouping: specific subjects before general ones.
SUBJECTS = [
    ("Trial balance intake", (
        "tb_submission", "amount_basis", "trial_balance_balances", "batches_balance",
        "year_end_close", "tb_entity", "entity_less_gl", "submission",
        "tb_movements", "silver_gl", "topside")),
    ("Currency and translation", (
        "exchange_rate", "historical_rate", "equity_rate", "translated", "cta",
        "currency", "conversion_factor", "fx_", "governed_rate", "rate_",
        "historical_is_equity_only", "declared_historical")),
    ("Ownership and the consolidated result", (
        "ownership", "group_amount", "nci", "consolidation_group", "consolidation_node",
        "fctb", "all_layers", "draft_excluded", "hierarchy_rollup", "end_to_end")),
    ("Acquisitions and disposals", (
        "acquisition", "acquired", "disposal", "goodwill", "bargain", "deal_",
        "measured_in_period", "proration")),
    ("Intercompany", ("ic_", "intercompany", "unrealized", "reciprocal")),
    ("Equity method", ("equity_method", "equity_income")),
    ("Cash flow", ("cf_", "cash_flow", "consolidated_cf")),
    ("Reporting hierarchies", ("hierarchy", "node", "unassigned")),
    ("Budget, forecast and variance", (
        "budget", "variance", "spread", "favorable", "scenario", "allocation",
        "driver", "composite")),
    ("The chart of accounts", ("account", "chart", "pnl_or_balance_sheet", "bs_only")),
    ("Calendar and periods", ("fiscal", "period_", "calendar")),
    ("Platform and data integrity", (
        "decimal", "cast", "grain_unique", "populated", "d365", "adjustment_type",
        "reversal", "auto_", "grain", "incremental", "stale", "is_credit_retired",
        "partner_grain", "fanned_out", "scope_resolves", "prior_year")),
]

LEAD = re.compile(r"^\s*(--\s?|\{#\s*|#\s*)")
STOP = re.compile(r"^\s*(select|with|\{\{|\{%|#\})", re.I)
ISSUE = re.compile(r"\b(konsol|konsolidat)#(\d+)\b")
BARE = re.compile(r"(?<![\w#])#(\d{2,4})\b")
SEV = re.compile(r"severity\s*=\s*['\"](\w+)['\"]")


def header(text: str) -> str:
    """The leading comment block, as plain prose."""
    out, in_jinja = [], False
    for line in text.splitlines():
        s = line.strip()
        if s.startswith("{#"):
            in_jinja = True
            s = s[2:].strip()
        if in_jinja:
            if "#}" in s:
                out.append(s.split("#}")[0].strip())
                break
            out.append(s)
            continue
        if s.startswith("--"):
            out.append(s.lstrip("-").strip())
            continue
        if not s:
            if out:
                continue
            continue
        if STOP.match(s) or s.startswith("{{"):
            break
    return " ".join(p for p in out if p).strip()


def subject(name: str, body: str) -> str:
    hay = name.lower()
    for title, words in SUBJECTS:
        if any(w in hay for w in words):
            return title
    return "Other"


def rule_sentence(prose: str) -> str:
    """The first sentence — the rule itself, before the history."""
    if not prose:
        return ""
    prose = re.sub(r"^(Test:|PRD-\d+ test:)\s*", "", prose).strip()
    m = re.search(r"(?<=[.;])\s+", prose)
    first = prose[: m.start() + 1] if m else prose
    return first.strip()


def main() -> int:
    files = sorted(TESTS.glob("assert_*.sql"))
    if not files:
        print(f"no assertions under {TESTS}", file=sys.stderr)
        return 1

    rows = []
    for f in files:
        text = f.read_text(encoding="utf-8", errors="replace")
        prose = header(text)
        sev = SEV.search(text)
        issues = {f"{r}#{n}" for r, n in ISSUE.findall(text)}
        issues |= {f"konsolidat#{n}" for n in BARE.findall(text)} - {
            f"konsolidat#{n}" for r, n in ISSUE.findall(text) for _ in (0,)
        }
        rows.append({
            "name": f.stem.removeprefix("assert_"),
            "file": f.name,
            "rule": rule_sentence(prose),
            "prose": prose,
            "severity": sev.group(1) if sev else "error (default)",
            "issues": sorted(issues),
            "subject": subject(f.stem, prose),
        })

    by_subject: dict[str, list] = {}
    for r in rows:
        by_subject.setdefault(r["subject"], []).append(r)

    documented = sum(1 for r in rows if r["rule"])
    cited = sum(1 for r in rows if r["issues"])
    warns = sum(1 for r in rows if r["severity"] == "warn")

    L = []
    w = L.append
    w("# The rules the warehouse enforces")
    w("")
    w("_Generated by `scripts/extract_assertion_rules.py`. **Do not edit this file** —")
    w("edit the test it came from and run the script again._")
    w("")
    w("Every rule below is a singular dbt test. Each one exists because a wrong")
    w("number reached someone once. The test is the fix; this page is the reason,")
    w("lifted out of the file so the set can be read as a body of knowledge rather")
    w("than found one assertion at a time.")
    w("")
    w("A rebuild that re-derived the models but not these rules would be a")
    w("consolidation engine with every defect this one has already paid for.")
    w("")
    w(f"| | |")
    w(f"|---|---|")
    w(f"| assertions | **{len(rows)}** |")
    w(f"| carrying their reasoning | {documented} |")
    w(f"| citing the issue that caused them | {cited} |")
    w(f"| severity `warn` (reports, does not stop a build) | {warns} |")
    w(f"| severity `error` (stops the build, and its children) | {len(rows) - warns} |")
    w("")
    w("**`warn` is not a weaker rule — it is a different kind.** An error says the")
    w("number is wrong; a warning says it is unexplained. See konsol#247.")
    w("")
    w("## Contents")
    w("")
    for title, _ in SUBJECTS + [("Other", ())]:
        if title in by_subject:
            anchor = title.lower().replace(" ", "-").replace(",", "")
            w(f"- [{title}](#{anchor}) — {len(by_subject[title])}")
    w("")

    for title, _ in SUBJECTS + [("Other", ())]:
        group = by_subject.get(title)
        if not group:
            continue
        w("---")
        w("")
        w(f"## {title}")
        w("")
        for r in sorted(group, key=lambda x: x["name"]):
            w(f"### `{r['name']}`")
            w("")
            if r["rule"]:
                w(f"**{r['rule']}**")
                w("")
            rest = r["prose"][len(r["rule"]):].strip() if r["rule"] else r["prose"]
            if rest:
                w(rest)
                w("")
            bits = [f"`{r['severity']}`", f"`tests/{r['file']}`"]
            if r["issues"]:
                bits.append(" ".join(r["issues"]))
            w("<sub>" + " · ".join(bits) + "</sub>")
            w("")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(L) + "\n", encoding="utf-8")
    print(f"{OUT.relative_to(ROOT)}: {len(rows)} assertions, "
          f"{len(by_subject)} subjects, {cited} citing an issue")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
