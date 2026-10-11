#!/usr/bin/env python3
"""The test_fixtures gate: prove a singular test can fail (konsolidat#266).

A fixture under dbt_project/test_fixtures/ seeds the rows one test is checked
against. `<name>.must_flag.sql` must make its test FAIL or WARN; any other
fixture must make it PASS. A test that cannot fail passes both, so the gate
catches it (konsolidat#249 and #238 were exactly that). Until #266 the script
that ran the fixtures lived in a maintainer's scratch checkout and no CI job
read the folder; decided by Deepak Pai, 11 Oct 2026, option G-1: commit the
gate and run every fixture in CI. Rejected: G-2, keep it manual.

Isolation. Nothing named epm_* is written. Per fixture the gate:

  1. drops and recreates the scratch databases zzg, zzg_raw, zzg_staging,
     zzg_bronze, zzg_silver, zzg_gold;
  2. creates, EMPTY and with the DDL of the matching epm_* table, every table
     the fixture file names (comments included, so a fixture names a model's
     other inputs in a comment to get them created), every declared dbt
     source, and in test mode every relation the selected tests read;
  3. runs the fixture with epm_ rewritten to zzg_ (ALTERs and CREATEs first,
     in file order, as written) and prints `fixture <table>: N rows`;
  4. runs dbt on a copy of the project whose epm_* schemas are rewritten to
     zzg_* (scripts/tb_only_first_build.py copy_project), reads
     target/run_results.json and judges the outcome;
  5. drops the scratch databases.

Where the DDL comes from. Live, the epm_* tables are the stack's own. In CI
there is no live stack, so `--prepare-ci` first builds one on the throwaway
ClickHouse: clickhouse/init-db.sql and raw-schema.sql (as ci_full_build.py
applies them), then `dbt run` of the whole project at the real dimensions.
The DDL is taken from that build, not from clickhouse/*.sql alone, because
those files declare only the sources: every model table a fixture seeds
(gold_trial_balance, silver_entity_currencies, ...) exists only once dbt has
built it, and its columns are what the model's SQL makes them.

What a fixture declares. Optional `-- gate:` lines, anywhere in the file:

    -- gate: build <dbt selector ...>   run `dbt build --select <selector>`
                                        (default: `dbt test --select <tests>`)
    -- gate: expect <test> pass|flag [N]  judge this test (repeatable); N is
                                        the exact result count when flagged
    -- gate: expect <model> built       the model must build (a fixture whose
                                        rule is the model's own guard)
    -- gate: refuse <model> <text>      the build must ERROR on <model> with
                                        <text> in the log (a pre_hook guard)

With no `expect`, the test is the file name up to its first dot, and the
expectation is `flag` for `.must_flag.` and `pass` otherwise. A plain fixture
that declares `flag` is refused: the file name is the contract. In build mode
an ERROR on any model fails the fixture unless `refuse` names it.

Usage:

    python scripts/fixture_gate.py <fixture.sql> [...]     # some fixtures
    python scripts/fixture_gate.py --all                   # every fixture
    python scripts/fixture_gate.py --all --prepare-ci      # CI: build first

`--prepare-ci` writes the epm_* databases, so it refuses to run unless the
warehouse is declared disposable (CI=true or --yes-destroy-this-warehouse),
as ci_full_build.py does.

Connection: CLICKHOUSE_HOST / PORT / USER / PASSWORD (HTTP interface).
"""

import argparse
import json
import os
import re
import shlex
import subprocess
import sys
import tempfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(REPO, "scripts"))

from tb_only_first_build import (  # noqa: E402
    LAYERS, copy_project, rewrite, run_dbt, split_sql,
)

FIXTURES = os.path.join(REPO, "dbt_project", "test_fixtures")
TESTS = os.path.join(REPO, "dbt_project", "tests")
PREFIX = "zzg"
SCRATCH_DBS = [PREFIX] + [f"{PREFIX}_{layer}" for layer in LAYERS]
TABLE_RE = re.compile(r"\bepm_(%s)\.([A-Za-z0-9_]+)" % "|".join(LAYERS))
INSERT_RE = re.compile(r"^\s*INSERT\s+INTO\s+(zzg_\w+\.\w+)", re.I)
DIRECTIVE_RE = re.compile(r"^--\s*gate:\s*(\w+)\s*(.*?)\s*$", re.M)
FLAGGED = ("fail", "warn")
LEAK_RE = re.compile(r"\bepm_(%s)\b|['\"]epm_?['\"]" % "|".join(LAYERS))


# ── the fixture's contract ──────────────────────────────────────────────────

def spec(path):
    """What the fixture asks for: mode, selector, expectations."""
    name = os.path.basename(path)
    with open(path, encoding="utf-8") as f:
        text = f.read()
    must_flag = ".must_flag." in name
    s = {"name": name, "text": text, "mode": "test", "selector": None,
         "expect": [], "refuse": None, "must_flag": must_flag}
    for key, arg in DIRECTIVE_RE.findall(text):
        if key == "build":
            s["mode"], s["selector"] = "build", shlex.split(arg)
        elif key == "expect":
            parts = arg.split()
            if len(parts) not in (2, 3) or parts[1] not in ("pass", "flag", "built"):
                raise SystemExit(f"{name}: bad directive `gate: expect {arg}`")
            s["expect"].append((parts[0], parts[1], int(parts[2]) if len(parts) == 3 else None))
        elif key == "refuse":
            model, _, needle = arg.partition(" ")
            s["refuse"] = (model, needle.strip().strip('"'))
        else:
            raise SystemExit(f"{name}: unknown directive `gate: {key}`")
    if not s["expect"] and not s["refuse"]:
        test = name.split(".")[0]
        s["expect"] = [(test, "flag" if must_flag else "pass", None)]
    for test, verdict, _n in s["expect"]:
        if verdict != "built" and not os.path.exists(os.path.join(TESTS, test + ".sql")):
            raise SystemExit(f"{name}: no singular test {test} in dbt_project/tests")
    if (s["refuse"] or any(v == "built" for _t, v, _n in s["expect"])) and s["mode"] != "build":
        raise SystemExit(f"{name}: `built` and `refuse` need a `gate: build` selector")
    # The file name is the contract: a plain fixture never expects a flag, and a
    # must_flag fixture must expect one (or a refused build).
    flags = [t for t, v, _ in s["expect"] if v == "flag"]
    if not must_flag and (flags or s["refuse"]):
        raise SystemExit(f"{name}: a plain fixture must PASS; rename it .must_flag. to expect {flags or 'a refusal'}")
    if must_flag and not (flags or s["refuse"]):
        raise SystemExit(f"{name}: a .must_flag. fixture expects nothing to flag")
    return s


# ── scratch warehouse ───────────────────────────────────────────────────────

def client_from_env():
    import clickhouse_connect

    return clickhouse_connect.get_client(
        host=os.environ.get("CLICKHOUSE_HOST", "localhost"),
        port=int(os.environ.get("CLICKHOUSE_PORT", "8123")),
        username=os.environ.get("CLICKHOUSE_USER", "default"),
        password=os.environ.get("CLICKHOUSE_PASSWORD", ""),
    )


def reset_scratch(client, create=True):
    for db in SCRATCH_DBS:
        client.command(f"DROP DATABASE IF EXISTS {db}")
    if create:
        for db in SCRATCH_DBS:
            client.command(f"CREATE DATABASE {db}")


def epm_tables(client):
    """{'epm_gold.gold_trial_balance': engine} for every table the stack has."""
    rows = client.query(
        "select database, name, engine from system.tables where match(database, '^epm_(%s)$')"
        % "|".join(LAYERS)).result_rows
    return {f"{d}.{n}": e for d, n, e in rows}


def clone_empty(client, epm_name, engine):
    zzg_name = rewrite(epm_name, PREFIX)
    if engine in ("View", "MaterializedView"):
        # A view's structure, as a table: the scratch copy holds no query.
        client.command(f"CREATE TABLE IF NOT EXISTS {zzg_name} ENGINE = MergeTree ORDER BY tuple() "
                       f"AS SELECT * FROM {epm_name} LIMIT 0")
    else:
        client.command(f"CREATE TABLE IF NOT EXISTS {zzg_name} AS {epm_name}")


def manifest_relations(manifest):
    """{unique_id: 'epm_<layer>.<table>'} for every model and source."""
    out = {}
    for uid, node in list(manifest["nodes"].items()) + list(manifest["sources"].items()):
        if node.get("resource_type") not in ("model", "source"):
            continue
        schema = node.get("schema") or ""
        database = node.get("database") or ""
        db = schema if schema.startswith(PREFIX) else database
        ident = node.get("identifier") or node.get("alias") or node["name"]
        if re.fullmatch(r"%s_(%s)" % (PREFIX, "|".join(LAYERS)), db or ""):
            out[uid] = "epm_" + db[len(PREFIX) + 1:] + "." + ident
    return out


def test_parents(manifest, tests):
    parents = set()
    for uid, node in manifest["nodes"].items():
        if node.get("resource_type") == "test" and node["name"] in tests:
            parents.update(node["depends_on"]["nodes"])
    return parents


# ── one fixture ─────────────────────────────────────────────────────────────

def run_fixture(client, dbt, project, manifest, tables, s, log_dir):
    print(f"\n== {s['name']}", flush=True)
    reset_scratch(client)
    relations = manifest_relations(manifest)
    wanted = {f"epm_{layer}.{t}" for layer, t in TABLE_RE.findall(s["text"])}
    wanted |= {rel for uid, rel in relations.items() if uid.startswith("source.")}
    tests = [t for t, v, _n in s["expect"] if v != "built"]
    if s["mode"] == "test":
        wanted |= {relations[uid] for uid in test_parents(manifest, tests) if uid in relations}
    for name in sorted(wanted):
        if name in tables:
            clone_empty(client, name, tables[name])

    loaded = []
    for stmt in split_sql(rewrite(s["text"], PREFIX)):
        if re.search(r"\bepm_", stmt):
            raise SystemExit(f"{s['name']}: unrewritten epm_ reference: {stmt[:120]}")
        client.command(stmt)
        m = INSERT_RE.match(stmt)
        if m and m.group(1) not in loaded:
            loaded.append(m.group(1))
    for t in loaded:
        n = client.command(f"select count() from {t}")
        print(f"    fixture {t}: {n} rows", flush=True)

    if s["mode"] == "build":
        # cautious: a test runs only when ALL its parents are selected, so the
        # build does not drag in a test whose other inputs this fixture never
        # created. The fixture's own tests are named, so they always run.
        args = ["build", "--indirect-selection", "cautious", "--select"] + s["selector"]
    else:
        args = ["test", "--select"] + tests
    log = os.path.join(log_dir, s["name"] + ".log")
    code, out = run_dbt(dbt, project, args, log)
    results = load_results(project)
    for line in out.splitlines():
        if re.search(r"\b(PASS|FAIL|WARN|ERROR|SKIP)\b.*\b(assert_|gold_|silver_|bronze_)|Got \d+ result", line):
            print("    " + line.strip(), flush=True)
    problems = judge(s, results, out)
    reset_scratch(client, create=False)
    for p in problems:
        print(f"    PROBLEM: {p}", flush=True)
    return ("ok" if not problems else "failed"), problems


def load_results(project):
    path = os.path.join(project, "target", "run_results.json")
    if not os.path.exists(path):
        return {}
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    out = {}
    for r in data.get("results", []):
        name = r["unique_id"].split(".")[-1] if r["unique_id"].startswith("test.") else r["unique_id"].split(".")[2]
        out[name] = (r["unique_id"].split(".")[0], r["status"], r.get("failures"), r.get("message") or "")
    return out


def judge(s, results, out):
    problems = []
    if not results:
        return ["dbt wrote no run_results.json: nothing ran"]
    for test, verdict, n in s["expect"]:
        got = results.get(test)
        if got is None:
            problems.append(f"{test} did not run (not selected, or the build stopped before it)")
            continue
        _kind, status, failures, _msg = got
        if verdict == "built" and status != "success":
            problems.append(f"{test} must build, got {status.upper()}")
        if verdict == "pass" and status != "pass":
            problems.append(f"{test} must PASS, got {status.upper()} {failures or ''}".rstrip())
        if verdict == "flag":
            if status not in FLAGGED:
                problems.append(f"{test} must FAIL or WARN, got {status.upper()} — a test that cannot fail")
            elif n is not None and failures != n:
                problems.append(f"{test} must flag exactly {n}, got {failures}")
    model_errors = {name: msg for name, (kind, status, _f, msg) in results.items()
                    if kind == "model" and status == "error"}
    if s["refuse"]:
        model, needle = s["refuse"]
        if model not in model_errors:
            problems.append(f"{model} must be REFUSED (ERROR), got "
                            f"{results.get(model, ('', 'not run'))[1].upper()}")
        elif needle and needle not in out and needle not in model_errors[model]:
            problems.append(f"{model} errored, but not with {needle!r}")
        model_errors.pop(model, None)
    for model, msg in model_errors.items():
        problems.append(f"model {model} ERROR: {msg.splitlines()[0][:200] if msg else ''}")
    for name, (kind, status, _f, msg) in results.items():
        if status == "error" and kind == "test":
            problems.append(f"test {name} ERROR: {msg.splitlines()[0][:200] if msg else ''}")
    return problems


# ── CI: a stack to take the DDL from ────────────────────────────────────────

def prepare_ci(client, dbt, log_dir):
    """The epm_* shape a deployed stack has: sources from clickhouse/*.sql,
    models from a full `dbt run` at the real dimensions."""
    from ci_full_build import PROJECT, apply_schema

    apply_schema(client)
    code, out = run_dbt(dbt, PROJECT, ["run"], os.path.join(log_dir, "prepare-run.log"))
    m = re.search(r"Done\. .*", out)
    print("    " + (m.group(0) if m else f"no dbt summary (exit {code})"), flush=True)
    if code != 0:
        sys.exit(f"--prepare-ci: dbt run failed (exit {code}); see {log_dir}/prepare-run.log")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("fixtures", nargs="*", help="fixture files (default with --all: every one)")
    ap.add_argument("--all", action="store_true", help="run every fixture in dbt_project/test_fixtures")
    ap.add_argument("--dbt", default="dbt", help="dbt executable")
    ap.add_argument("--prepare-ci", action="store_true",
                    help="first build the epm_* shape on this (throwaway) ClickHouse")
    ap.add_argument("--yes-destroy-this-warehouse", action="store_true",
                    help="confirm the target ClickHouse is disposable (for --prepare-ci)")
    ap.add_argument("--log-dir", default=None, help="where to write the dbt logs")
    a = ap.parse_args()

    paths = sorted(os.path.join(FIXTURES, f) for f in os.listdir(FIXTURES) if f.endswith(".sql")) \
        if a.all else [os.path.abspath(p) for p in a.fixtures]
    if not paths:
        sys.exit("no fixtures: name some, or pass --all")
    specs = [spec(p) for p in paths]  # every contract is checked before anything runs

    log_dir = a.log_dir or os.path.join(REPO, "ci-logs", "fixtures")
    os.makedirs(log_dir, exist_ok=True)
    client = client_from_env()

    if a.prepare_ci:
        if not (a.yes_destroy_this_warehouse or os.environ.get("CI") == "true"):
            sys.exit("refusing --prepare-ci: it writes the epm_* databases. Run it only against a "
                     "throwaway warehouse (CI=true, or --yes-destroy-this-warehouse).")
        print("== prepare: clickhouse/*.sql, then dbt run (the DDL the fixtures are cloned from)", flush=True)
        prepare_ci(client, a.dbt, log_dir)

    tables = epm_tables(client)
    if not tables:
        sys.exit("no epm_* tables here: nothing to take the DDL from (CI: pass --prepare-ci)")

    work = tempfile.mkdtemp(prefix="fixture_gate_")
    project = os.path.join(work, "dbt_project")
    copy_project(PREFIX, project)
    leaks = []
    for root, _d, files in os.walk(project):
        for fn in files:
            if fn.endswith((".sql", ".yml", ".yaml")) and "test_fixtures" not in root:
                with open(os.path.join(root, fn), encoding="utf-8") as f:
                    # A schema the rewrite missed: a qualified epm_<layer> name, or one
                    # assembled from a literal ('epm_' ~ layer, 'epm' ~ ...).
                    if LEAK_RE.search(f.read()):
                        leaks.append(os.path.join(root, fn))
    if leaks:
        sys.exit(f"refusing: the project copy still names epm_ in {leaks[:5]}")
    reset_scratch(client)
    code, out = run_dbt(a.dbt, project, ["parse"], os.path.join(log_dir, "parse.log"))
    if code != 0:
        sys.exit(f"dbt parse failed (exit {code}); see {log_dir}/parse.log")
    with open(os.path.join(project, "target", "manifest.json"), encoding="utf-8") as f:
        manifest = json.load(f)

    verdicts = []
    try:
        for s in specs:
            verdict, problems = run_fixture(client, a.dbt, project, manifest, tables, s, log_dir)
            verdicts.append((s["name"], verdict, problems))
    finally:
        reset_scratch(client, create=False)

    print("\n== fixtures")
    for name, verdict, problems in verdicts:
        print(f"    {verdict.upper():8} {name}" + (f"  — {problems[0]}" if problems else ""))
    failed = [v for v in verdicts if v[1] == "failed"]
    ok = sum(1 for v in verdicts if v[1] == "ok")
    print(f"\nfixtures: {ok} ok, {len(failed)} failed, {len(verdicts)} total")
    if failed:
        sys.exit(f"FAILED: {len(failed)} fixture(s) did not behave; logs in {log_dir}")


if __name__ == "__main__":
    main()
