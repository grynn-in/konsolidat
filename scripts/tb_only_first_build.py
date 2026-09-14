#!/usr/bin/env python3
"""The first dbt build on a fresh, trial-balance-only site (konsol#182).

A site that takes its figures from uploaded trial balances has no ERP rows, no
allocation rules and no ERP exchange-rate quotes. Its warehouse is exactly what
a fresh ClickHouse volume gets: clickhouse/init-db.sql and
clickhouse/raw-schema.sql, every table empty. This script builds that shape
under a scratch prefix and runs

    dbt build --select @silver_main_accounts

(the chart model, everything downstream of it, and all their ancestors), then
requires ERROR=0 and the literal `OK created` for silver_main_accounts and
gold_consolidated_trial_balance.

Nothing named epm_* is touched. The databases are <prefix>, <prefix>_staging,
<prefix>_gold, <prefix>_raw, ... ; a copy of the dbt project has every epm_*
schema rewritten to the prefix, and its own profiles.yml (schema: <prefix>), so
models land beside their sources exactly as they do on a real stack. The prefix
must not exist yet; everything it creates is dropped at the end (--keep to
inspect it).

--fixture also loads a small ZZ data set (a published chart, one entity, one
group, one claimed TB submission, one allocation rule) and checks the same
selection still builds with rows in gold_consolidated_trial_balance. It then
plants one bad ERP quote in <prefix>_silver.silver_exchange_rates and requires
the ERP-quote tests to flag it, so a TB-only guard cannot hide a real problem.

Connection: CLICKHOUSE_HOST / CLICKHOUSE_PORT / CLICKHOUSE_USER /
CLICKHOUSE_PASSWORD (HTTP interface). Needs dbt-core + dbt-clickhouse, which
bring clickhouse-connect.

    python scripts/tb_only_first_build.py --prefix kab_fb [--fixture] [--dbt PATH]
"""

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LAYERS = ("staging", "gold", "raw", "bronze", "silver", "allocated")
SCHEMA_RE = re.compile(r"\bepm_(?=(?:%s)\b)" % "|".join(LAYERS))
BARE_DB_RE = re.compile(r"\bepm(?=\s*;)")  # CREATE DATABASE IF NOT EXISTS epm;
MUST_CREATE = ("silver_main_accounts", "gold_consolidated_trial_balance")
ERP_QUOTE_TESTS = ("assert_exchange_rate_currencies_are_iso", "assert_exchange_rate_sane_magnitude")
# #191: cast_to_decimal128's regression test. The empty-site build already
# selects it (its `-- depends_on:` makes it reachable from @silver_main_accounts),
# but show() never names a passing test, so the log can't show it ran. Run it
# by name as a must-pass check, so a regression fails the job under its own name.
CAST_TEST = "assert_cast_to_decimal128_is_exact"


def rewrite(text, prefix):
    text = SCHEMA_RE.sub(prefix + "_", text)
    return BARE_DB_RE.sub(prefix, text)


def split_sql(text):
    """Statements separated by ';', ignoring -- comments and quoted text."""
    out, buf, i, quoted = [], [], 0, False
    while i < len(text):
        c = text[i]
        if quoted:
            buf.append(c)
            if c == "\\" and i + 1 < len(text):
                buf.append(text[i + 1])
                i += 1
            elif c == "'":
                quoted = False
        elif c == "'":
            quoted = True
            buf.append(c)
        elif text.startswith("--", i):
            while i < len(text) and text[i] != "\n":
                i += 1
            continue
        elif c == ";":
            out.append("".join(buf).strip())
            buf = []
        else:
            buf.append(c)
        i += 1
    out.append("".join(buf).strip())
    return [s for s in out if s]


def copy_project(prefix, dest):
    src = os.path.join(REPO, "dbt_project")
    shutil.copytree(src, dest, ignore=shutil.ignore_patterns("target", "logs", "dbt_packages", "* 2.*"))
    for root, _dirs, files in os.walk(dest):
        for name in files:
            if name.endswith((".sql", ".yml", ".yaml")):
                path = os.path.join(root, name)
                with open(path, encoding="utf-8") as f:
                    text = f.read()
                new = rewrite(text, prefix)
                if new != text:
                    with open(path, "w", encoding="utf-8") as f:
                        f.write(new)
    with open(os.path.join(dest, "profiles.yml"), "w", encoding="utf-8") as f:
        f.write(
            "open_epm:\n"
            "  target: scratch\n"
            "  outputs:\n"
            "    scratch:\n"
            "      type: clickhouse\n"
            "      host: \"{{ env_var('CLICKHOUSE_HOST', 'localhost') }}\"\n"
            "      port: \"{{ env_var('CLICKHOUSE_PORT', '8123') | int }}\"\n"
            "      user: \"{{ env_var('CLICKHOUSE_USER', 'default') }}\"\n"
            "      password: \"{{ env_var('CLICKHOUSE_PASSWORD', '') }}\"\n"
            "      schema: %s\n"
            "      secure: false\n"
            "      verify: false\n"
            "      connect_timeout: 30\n"
            "      send_receive_timeout: 300\n" % prefix
        )


def fixture_sql(p):
    chart_cols = (
        "main_account, account_name, chart_of_accounts, parent_account, is_group, account_type, "
        "statement_section, sub_section, normal_balance, time_balance, fx_method, is_posting, "
        "is_suspended, allow_ic, cf_category, cf_line_item, is_cash, main_account_category, status"
    )
    return [
        f"INSERT INTO {p}_staging.main_accounts ({chart_cols}) VALUES "
        "('ZZ', 'ZZ group chart', 'ZZCOA', '', 1, '', '', '', '', '', '', 0, 0, 0, '', '', 0, '', 'Published'), "
        "('ZZ1000', 'ZZ cash', 'ZZCOA', 'ZZ', 0, 'Asset', 'Balance Sheet', 'Current Assets', 'Debit', 'Balance', 'closing', 1, 0, 0, '', '', 1, 'CASH', 'Published'), "
        "('ZZ3000', 'ZZ share capital', 'ZZCOA', 'ZZ', 0, 'Equity', 'Balance Sheet', 'Equity', 'Credit', 'Balance', 'historical', 1, 0, 0, '', '', 0, 'EQUITY', 'Published'), "
        "('ZZ4000', 'ZZ revenue', 'ZZCOA', 'ZZ', 0, 'Revenue', 'Profit and Loss', 'Revenue', 'Credit', 'Period', 'average', 1, 0, 0, '', '', 0, 'REVENUE', 'Published')",
        # every balance-sheet account is categorised for the cash flow
        # (the relationships test on gold_bs_movement.main_account)
        f"INSERT INTO {p}_staging.cash_flow_categories VALUES "
        "('ZZ1000', 'Operating', 'Cash', 1, 1, 'Published'), "
        "('ZZ3000', 'Financing', 'Share capital', 0, 1, 'Published')",
        f"INSERT INTO {p}_staging.entities VALUES ('ZZOP', 'ZZ Operating', 'ZZGRP', 0, 'Active', 'USD', 'US', '')",
        f"INSERT INTO {p}_gold.consolidation_groups (consolidation_group, data_area_id, entity_name, reporting_currency) VALUES "
        "('ZZGRP', '', 'ZZ Group', 'USD'), ('ZZGRP', 'ZZOP', 'ZZ Operating', 'USD')",
        f"INSERT INTO {p}_staging.consolidation_hierarchy (consolidation_group, data_area_id, parent_group, hierarchy_level, path) VALUES "
        "('ZZGRP', 'ZZOP', '', 1, 'ZZGRP')",
        f"INSERT INTO {p}_staging.consolidation_ancestry VALUES ('ZZGRP', 'ZZOP', 'ZZGRP', 'ZZOP', 1, 1, 'ZZGRP/ZZOP')",
        f"INSERT INTO {p}_staging.ownership_periods (consolidation_group, data_area_id, effective_date, ownership_pct, consolidation_method) VALUES "
        "('ZZGRP', 'ZZOP', '2020-01-01', 100, 'full')",
        f"INSERT INTO {p}_gold.currencies VALUES ('USD', 'US Dollar', '$', 2, 0)",
        f"INSERT INTO {p}_raw.trial_balance_submissions (batch_id, data_area_id, fiscal_year, fiscal_period, main_account, debit_amount, credit_amount, description, submission_name, submitted_at) VALUES "
        "('ZZB1', 'ZZOP', 2026, 1, 'ZZ1000', 150, 0, '', 'ZZ-TBS-1', now()), "
        "('ZZB1', 'ZZOP', 2026, 1, 'ZZ3000', 0, 50, '', 'ZZ-TBS-1', now()), "
        "('ZZB1', 'ZZOP', 2026, 1, 'ZZ4000', 0, 100, '', 'ZZ-TBS-1', now())",
        f"INSERT INTO {p}_raw.trial_balance_submission_control VALUES ('ZZB1', 'ZZ-TBS-1', 'ZZOP', 2026, 1, 3, now())",
        f"INSERT INTO {p}_staging.allocation_rules (allocation_rule_id, rule_name, step_order, source_account, source_cost_center, driver_type, target_account) VALUES "
        "('ZZAR1', 'ZZ rule', 1, 'ZZ4000', 'ZZCC', 'headcount', 'ZZ4000')",
    ]


def run_dbt(dbt, project, args, log_path):
    cmd = [dbt, "--no-use-colors"] + args + ["--project-dir", project, "--profiles-dir", project]
    print("$ " + " ".join(cmd), flush=True)
    proc = subprocess.run(cmd, cwd=project, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    with open(log_path, "w", encoding="utf-8") as f:
        f.write(proc.stdout)
    return proc.returncode, proc.stdout


def summary(out):
    """{'PASS': n, 'WARN': n, 'ERROR': n, ...} from dbt's `Done.` line."""
    m = re.search(r"Done\. ((?:[A-Z-]+=\d+ ?)+)", out)
    return {k: int(v) for k, v in re.findall(r"([A-Z-]+)=(\d+)", m.group(1))} if m else None


def created(out, prefix, model):
    """dbt-clickhouse prints `OK created sql table model `<schema>`.`<model>``."""
    return re.search(r"OK created .*`?%s_\w+`?\.`?%s\b" % (re.escape(prefix), model), out) is not None


def show(out):
    for line in out.splitlines():
        if re.search(r"\b(ERROR|FAIL|WARN)\b|OK created .*(%s)\b|Done\. PASS=" % "|".join(MUST_CREATE), line):
            print("    " + line.rstrip())


def build_selection(dbt, project, prefix, log_dir, label, extra=()):
    code, out = run_dbt(dbt, project, ["build", "--select", "@silver_main_accounts", *extra],
                        os.path.join(log_dir, f"{label}.log"))
    show(out)
    problems = []
    s = summary(out)
    if s is None:
        problems.append(f"{label}: no dbt summary line (exit {code})")
    elif s.get("ERROR"):
        problems.append(f"{label}: ERROR={s['ERROR']}")
    for model in MUST_CREATE:
        if not created(out, prefix, model):
            problems.append(f"{label}: no 'OK created' for {model}")
    return problems


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--prefix", required=True, help="scratch database prefix, e.g. kab_fb (never epm*)")
    ap.add_argument("--fixture", action="store_true", help="also build with ZZ data and probe the ERP-quote tests")
    ap.add_argument("--dbt", default="dbt", help="dbt executable")
    ap.add_argument("--keep", action="store_true", help="keep the scratch databases and project copy")
    a = ap.parse_args()

    if not re.fullmatch(r"[a-z][a-z0-9_]*", a.prefix) or a.prefix.startswith("epm"):
        sys.exit(f"refusing prefix {a.prefix!r}: lowercase identifier required, and never epm*")

    import clickhouse_connect

    client = clickhouse_connect.get_client(
        host=os.environ.get("CLICKHOUSE_HOST", "localhost"),
        port=int(os.environ.get("CLICKHOUSE_PORT", "8123")),
        username=os.environ.get("CLICKHOUSE_USER", "default"),
        password=os.environ.get("CLICKHOUSE_PASSWORD", ""),
    )
    ours = [a.prefix] + [f"{a.prefix}_{layer}" for layer in LAYERS]
    existing = sorted(
        r[0] for r in client.query(
            "select name from system.databases where name = {p:String} or startsWith(name, {pu:String})",
            parameters={"p": a.prefix, "pu": a.prefix + "_"},
        ).result_rows
    )
    if existing:
        sys.exit(f"refusing: databases already exist under this prefix (not a fresh site): {existing}")

    work = tempfile.mkdtemp(prefix=f"{a.prefix}_")
    project = os.path.join(work, "dbt_project")
    problems = []
    try:
        for name in ("init-db.sql", "raw-schema.sql"):
            with open(os.path.join(REPO, "clickhouse", name), encoding="utf-8") as f:
                for stmt in split_sql(rewrite(f.read(), a.prefix)):
                    if re.search(r"\bepm_", stmt):
                        raise SystemExit(f"unrewritten epm_ reference in {name}: {stmt[:120]}")
                    client.command(stmt)
        copy_project(a.prefix, project)
        print(f"fresh TB-only shape created under {a.prefix}*; project copy at {project}")

        print("\n== empty site: dbt build --select @silver_main_accounts")
        problems += build_selection(a.dbt, project, a.prefix, work, "empty")

        print(f"\n== {CAST_TEST}: must pass (a pure-literal test, needs no fixture)")
        code, out = run_dbt(a.dbt, project, ["test", "--select", CAST_TEST],
                            os.path.join(work, "cast_test.log"))
        show(out)
        s = summary(out)
        if s is None:
            problems.append(f"{CAST_TEST}: no dbt summary line (exit {code})")
        elif s.get("ERROR") or s.get("PASS", 0) < 1:
            problems.append(f"{CAST_TEST}: expected a clean PASS, got {s}")

        if a.fixture:
            for stmt in fixture_sql(a.prefix):
                client.command(stmt)
            print("\n== ZZ fixture: dbt build --select @silver_main_accounts --full-refresh")
            problems += build_selection(a.dbt, project, a.prefix, work, "fixture", ["--full-refresh"])
            counts = {
                t: client.command(f"select count() from {a.prefix}_{t} where data_area_id = 'ZZOP'" if t != "silver.silver_main_accounts"
                                  else f"select count() from {a.prefix}_{t} where startsWith(main_account_id, 'ZZ')")
                for t in ("silver.silver_main_accounts", "gold.gold_trial_balance", "gold.gold_consolidated_trial_balance")
            }
            print(f"    ZZ rows: {counts}")
            for t, n in counts.items():
                if not n:
                    problems.append(f"fixture: no ZZ rows in {t}")

            print("\n== ERP quotes present: one bad quote must be flagged")
            client.command(
                f"CREATE TABLE {a.prefix}_silver.silver_exchange_rates (from_currency String, to_currency String, "
                "valid_from Date, valid_to Date, exchange_rate Float64, exchange_rate_type String, recid Int64) "
                "ENGINE = MergeTree ORDER BY (from_currency, to_currency, valid_from)"
            )
            client.command(
                f"INSERT INTO {a.prefix}_silver.silver_exchange_rates VALUES "
                "('ZZX', 'USD', '2026-01-01', '2026-12-31', -1.0, 'Closing', 1)"
            )
            code, out = run_dbt(a.dbt, project, ["test", "--select"] + list(ERP_QUOTE_TESTS),
                                os.path.join(work, "erp_quotes.log"))
            show(out)
            expect = {"assert_exchange_rate_currencies_are_iso": "FAIL", "assert_exchange_rate_sane_magnitude": "WARN"}
            for test, status in expect.items():
                if not re.search(r"\b%s\b.*\b%s\b" % (status, test), out):
                    problems.append(f"erp quotes: expected {status} from {test}")
    finally:
        if a.keep:
            print(f"\nkept: databases {ours}, project {work}")
        else:
            for db in ours:
                client.command(f"DROP DATABASE IF EXISTS {db}")
            shutil.rmtree(work, ignore_errors=True)
            print(f"\ndropped {ours} and {work}")

    if problems:
        print("\nFAILED:\n  " + "\n  ".join(problems))
        return 1
    print("\nOK: TB-only first build is clean")
    return 0


if __name__ == "__main__":
    sys.exit(main())
