"""konsol#182: epm_staging.main_accounts is created by two repos, identically.

konsol's `_REFERENCE_TABLE_DDL["epm_staging.main_accounts"]` creates the
table on every migrate (`ensure_reference_tables` runs
f"CREATE TABLE IF NOT EXISTS {table} {body}"), and this repo's
clickhouse/init-db.sql creates it on a fresh volume. Whichever runs first
wins, so a difference between the two texts is a table whose shape depends on
the order the stack came up in. KONSOL_BODY is konsol's string, verbatim; the
same pin lives in konsol's tests/test_main_account.py.
"""
import os

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INIT_DB = os.path.join(PROJECT_ROOT, "clickhouse", "init-db.sql")

TABLE = "epm_staging.main_accounts"
KONSOL_BODY = (
    "(main_account String, account_name String, chart_of_accounts String, "
    "parent_account String, is_group UInt8, account_type String, "
    "statement_section String, sub_section String, normal_balance String, "
    "time_balance String, fx_method String, is_posting UInt8, "
    "is_suspended UInt8, allow_ic UInt8, cf_category String, "
    "cf_line_item String, is_cash UInt8, main_account_category String, "
    "status String) "
    "ENGINE = MergeTree ORDER BY main_account"
)
EXPECTED_LINE = f"CREATE TABLE IF NOT EXISTS {TABLE} {KONSOL_BODY};"


def _statements_naming_the_table():
    with open(INIT_DB, encoding="utf-8") as f:
        lines = f.read().splitlines()
    return [line for line in lines
            if TABLE + " " in line + " " and not line.lstrip().startswith("--")]


def test_init_db_creates_the_governed_chart_once_with_konsols_text():
    assert _statements_naming_the_table() == [EXPECTED_LINE]


def test_the_governed_chart_columns_are_the_ones_silver_reads():
    columns = [c.strip().split(" ")[0]
               for c in KONSOL_BODY[1:KONSOL_BODY.index(")")].split(",")]
    model = os.path.join(PROJECT_ROOT, "dbt_project", "models", "silver",
                         "silver_main_accounts.sql")
    with open(model, encoding="utf-8") as f:
        sql = f.read()
    governed = sql[sql.index("governed as ("):sql.index("{%- else %}")]
    unread = [c for c in columns if c not in governed]
    # Every column appears in silver's governed branch: is_group and status as
    # its filters, the rest selected. A column added to the DDL that silver
    # never reads is either a mistake or needs a decision here.
    assert unread == [], unread
