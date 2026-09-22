#!/usr/bin/env python3
"""The whole warehouse, built and asserted on a throwaway ClickHouse (konsolidat#181).

CI ran `dbt parse`, a gold-domain coverage check, seven DDL contract tests and
one *scoped* build (`@silver_main_accounts`, scripts/tb_only_first_build.py).
`dbt parse` does not validate SQL, and the scoped build is not the project:
measured on the graph, **375 nodes, 310 reachable from that selection, 65 not**
— 24 ERP sources and 41 nodes, among them eight singular assertions that ran in
no CI job at all, including the three FX rate guards:

    assert_conversion_factor_known      assert_incremental_slice_preserved
    assert_exchange_rate_positive       assert_scope_resolves_to_entities
    assert_fx_magnitude_cases           assert_scoped_cash_flow_ytd_confined
    assert_hierarchy_no_circular_ref    assert_staging_not_stale

`tests/integration` never ran either: its `ch` fixture skips the whole suite
when ClickHouse is unreachable, and no job provided one, so it reported nothing.

This script therefore, against a warehouse it is allowed to destroy:

  1. applies clickhouse/init-db.sql and clickhouse/raw-schema.sql — the shape a
     fresh volume gets;
  2. loads the ZZ fixture (the same one the scoped-build job uses);
  3. runs a FULL `dbt build` — no `--select`, which is the whole point;
  4. runs it again with `dimensions: []`. konsolidat#220 — a site that declared
     no dimensions could not build at all, 53 call sites across five macros in
     three failure shapes — was found by hand and nothing stopped that class
     returning. Every macro that grows a `dim_select` call site is a fresh
     chance to reintroduce it, and the build is green at real dimensions while
     broken at zero;
  5. with --with-integration, runs `tests/integration`, failing on an error
     **or a skip**. Run for the first time against a throwaway on 19 Sep 2026
     that suite gave **7 failed, 30 passed, 5 skipped, 3 errors** — it had
     rotted while never running. konsolidat#227 settled it: 20 of the 30 tests
     were deleted (11 could not fail or skipped by construction, 5 duplicated
     this job, 4 only asserted the warehouse exists) and the 10 that cover what
     no other test reaches were made to pass. **The workflow now passes this
     flag.** Measured green from a clean warehouse on 22 Sep 2026: full build
     PASS=320 ERROR=0 SKIP=0, suite 10 passed 0 skipped, zero-dimension build
     PASS=321.

A skip is treated as a failure throughout. A suite that skips itself, and a
dbt node that is SKIPped because its parent failed, both report success having
checked nothing — which is the shape of defect this job exists to catch
(see konsol#248, where the host runner reported N/N passed while a whole file
had stopped importing).

Connection: CLICKHOUSE_HOST / PORT / USER / PASSWORD (HTTP interface).

SAFETY: this writes into the real `epm_*` databases, so it refuses to run
unless the warehouse is declared disposable — `CI=true` (GitHub Actions sets
it) or `--yes-destroy-this-warehouse`. Never point it at a live stack.

    python scripts/ci_full_build.py [--dbt PATH] [--with-integration]
"""

import argparse
import json
import os
import re
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(REPO, "scripts"))

from tb_only_first_build import fixture_sql, run_dbt, split_sql, summary  # noqa: E402

PROJECT = os.path.join(REPO, "dbt_project")
SCHEMA_SQL = ("clickhouse/init-db.sql", "clickhouse/raw-schema.sql")

#: No --select. The scoped build has its own job; narrowing here would
#: reintroduce exactly the coverage gap this job was added to close.
FULL_BUILD = ["build"]
#: konsolidat#220's standing guard.
ZERO_DIM_BUILD = ["build", "--full-refresh", "--vars", json.dumps({"dimensions": []})]


def apply_schema(client):
    for rel in SCHEMA_SQL:
        with open(os.path.join(REPO, rel), encoding="utf-8") as f:
            statements = split_sql(f.read())
        for stmt in statements:
            client.command(stmt)
        print(f"applied {rel} ({len(statements)} statements)", flush=True)


def load_fixture(client):
    statements = fixture_sql("epm")
    for stmt in statements:
        client.command(stmt)
    print(f"loaded ZZ fixture ({len(statements)} inserts)", flush=True)


def show(out, keep=r"\b(ERROR|FAIL|WARN)\b|Done\. PASS="):
    for line in out.splitlines():
        if re.search(keep, line):
            print("    " + line.rstrip(), flush=True)


def build(dbt, args, label, log_dir):
    """Run one dbt build; return the problems it should fail the job for."""
    print(f"\n== {label}", flush=True)
    code, out = run_dbt(dbt, PROJECT, list(args), os.path.join(log_dir, f"{label}.log"))
    show(out)
    s = summary(out)
    if s is None:
        # dbt can exit before printing `Done.`; a missing summary is not a pass.
        return [f"{label}: no dbt summary line (exit {code})"]
    problems = []
    if s.get("ERROR"):
        problems.append(f"{label}: ERROR={s['ERROR']}")
    if s.get("SKIP"):
        # A node is SKIPped when its parent failed: coverage that did not run.
        problems.append(f"{label}: SKIP={s['SKIP']} — a skipped node was not checked")
    if not s.get("PASS"):
        problems.append(f"{label}: PASS=0 — nothing was built")
    print(f"    -> {label}: " + " ".join(f"{k}={v}" for k, v in sorted(s.items())), flush=True)
    return problems


def integration(log_dir):
    """tests/integration, where a skip is a failure (konsolidat#181)."""
    print("\n== tests/integration", flush=True)
    cmd = [sys.executable, "-m", "pytest", "tests/integration", "-v", "--tb=short"]
    print("$ " + " ".join(cmd), flush=True)
    proc = subprocess.run(cmd, cwd=REPO, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, text=True)
    with open(os.path.join(log_dir, "integration.log"), "w", encoding="utf-8") as f:
        f.write(proc.stdout)
    for line in proc.stdout.splitlines():
        if re.search(r"PASSED|FAILED|ERROR|SKIPPED|=====", line):
            print("    " + line.rstrip(), flush=True)

    problems = []
    if proc.returncode != 0:
        problems.append(f"integration: pytest exit {proc.returncode}")
    # "3 skipped" in the summary line, or a SKIPPED verdict on any test.
    skipped = re.search(r"(\d+) skipped", proc.stdout)
    if skipped and int(skipped.group(1)):
        problems.append(
            f"integration: {skipped.group(1)} test(s) skipped — the suite skips itself "
            "when ClickHouse is unreachable, which reports success having checked nothing")
    if re.search(r"^no tests ran|collected 0 items", proc.stdout, re.M):
        problems.append("integration: no tests ran")
    return problems


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dbt", default="dbt", help="dbt executable")
    ap.add_argument("--with-integration", action="store_true",
                    help="also run tests/integration; a skip counts as a "
                         "failure (konsolidat#227)")
    ap.add_argument("--yes-destroy-this-warehouse", action="store_true",
                    help="confirm the target ClickHouse is disposable")
    ap.add_argument("--log-dir", default=None, help="where to write the dbt logs")
    a = ap.parse_args()

    if not (a.yes_destroy_this_warehouse or os.environ.get("CI") == "true"):
        sys.exit("refusing: this writes into the real epm_* databases. Run it only "
                 "against a throwaway warehouse (CI=true, or "
                 "--yes-destroy-this-warehouse).")

    log_dir = a.log_dir or os.path.join(REPO, "ci-logs")
    os.makedirs(log_dir, exist_ok=True)

    import clickhouse_connect

    client = clickhouse_connect.get_client(
        host=os.environ.get("CLICKHOUSE_HOST", "localhost"),
        port=int(os.environ.get("CLICKHOUSE_PORT", "8123")),
        username=os.environ.get("CLICKHOUSE_USER", "default"),
        password=os.environ.get("CLICKHOUSE_PASSWORD", ""),
    )

    apply_schema(client)
    load_fixture(client)

    problems = build(a.dbt, FULL_BUILD, "full-build", log_dir)

    # konsolidat#227: the integration suite runs BEFORE the zero-dimension leg,
    # and that order is load-bearing. The zero-dimension build leaves every
    # incremental gold table materialised without its dimension columns; a
    # later build at the site's real dimension count then fails
    # `Code: 20 NUMBER_OF_COLUMNS_DOESNT_MATCH (source: 16 and result: 13)` —
    # a 3-column difference, the three declared dimensions — because those
    # models append with a pre_hook DELETE and only --full-refresh rebuilds the
    # shape (konsol#261). Run the other way round, the integration suite fails
    # for a reason that has nothing to do with the integration suite.
    if a.with_integration:
        problems += integration(log_dir)

    # Last, and it runs even if something above failed: which leg is broken is
    # the useful signal, and hiding one behind the other is how a defect class
    # gets attributed to the wrong change.
    problems += build(a.dbt, ZERO_DIM_BUILD, "full-build-zero-dimensions", log_dir)

    print()
    if problems:
        for p in problems:
            print("PROBLEM: " + p)
        sys.exit(f"FAILED: {len(problems)} problem(s); logs in {log_dir}")
    ran = "; integration suite ran with no skips" if a.with_integration else ""
    print("OK: the full project builds at real and zero dimensions" + ran)


if __name__ == "__main__":
    main()
