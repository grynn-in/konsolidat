"""The materiality floor has one definition (konsolidat#209).

The half-cent floor below which an amount is treated as zero lives in the
`materiality_floor()` macro. No model, macro or test repeats the literal, so a
later change (a group-declared floor, a currency-scaled floor) is one edit.
"""
import os

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DBT = os.path.join(PROJECT_ROOT, "dbt_project")
LITERAL = "0.005"
ALLOWED = {os.path.join(DBT, "macros", "materiality.sql")}


def _files():
    for sub in ("models", "macros", "tests"):
        for root, _dirs, names in os.walk(os.path.join(DBT, sub)):
            for name in names:
                if name.endswith((".sql", ".yml", ".yaml")):
                    yield os.path.join(root, name)


def test_materiality_floor_macro_exists():
    path = os.path.join(DBT, "macros", "materiality.sql")
    assert os.path.exists(path), "macros/materiality.sql must define materiality_floor()"
    with open(path) as f:
        content = f.read()
    assert "macro materiality_floor()" in content
    assert LITERAL in content


def test_no_materiality_literal_outside_macro():
    hits = []
    for path in _files():
        if path in ALLOWED:
            continue
        with open(path) as f:
            for n, line in enumerate(f, 1):
                if LITERAL in line:
                    hits.append(f"{os.path.relpath(path, PROJECT_ROOT)}:{n}")
    assert not hits, f"{len(hits)} lines repeat {LITERAL}; use materiality_floor():\n" + "\n".join(hits)
