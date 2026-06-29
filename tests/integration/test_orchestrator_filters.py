"""Tests for the orchestrator scope/period filter macros (konsolidat#119).

These exercise dbt_project/macros/orchestrator_filters.sql by rendering each
macro through `dbt compile --inline` (which resolves ref() against the manifest)
and asserting on the compiled SQL. The escaping is additionally proven against a
live ClickHouse instance so we know the generated LIKE patterns behave.

Run with: pytest tests/integration/test_orchestrator_filters.py -v
Requires: dbt on PATH + a reachable ClickHouse (same as the other integration
tests). Tests skip cleanly if either is unavailable.
"""
import os
import re
import shutil
import subprocess

import pytest

DBT_DIR = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "..", "dbt_project")
)

_MARKER = "Compiled inline node is:"
_LOGLINE = re.compile(r"^\d{2}:\d{2}:\d{2}\b")


def _compile_inline(sql, dbt_vars=None):
    """Run `dbt compile --inline` and return (returncode, compiled_sql, full_output)."""
    cmd = [
        "dbt", "compile", "--inline", sql,
        "--project-dir", DBT_DIR, "--profiles-dir", DBT_DIR,
    ]
    if dbt_vars:
        cmd += ["--vars", dbt_vars]
    proc = subprocess.run(
        cmd, capture_output=True, text=True, timeout=180, cwd=DBT_DIR
    )
    out = (proc.stdout or "") + (proc.stderr or "")
    compiled = None
    if _MARKER in out:
        tail = out.split(_MARKER, 1)[1].splitlines()
        body = []
        for line in tail[1:] if tail and tail[0].strip() == "" else tail:
            if _LOGLINE.match(line.strip()) or "[WARNING]" in line or "[ERROR]" in line:
                break
            body.append(line)
        compiled = "\n".join(body).strip()
    return proc.returncode, compiled, out


@pytest.fixture(scope="module")
def dbt_available():
    if shutil.which("dbt") is None:
        pytest.skip("dbt not on PATH")
    # A trivial compile proves dbt can parse the project + open its connection.
    rc, compiled, out = _compile_inline("select 1")
    if rc != 0 or compiled is None:
        pytest.skip(f"dbt compile unavailable (no DB connection?):\n{out[-500:]}")
    return True


def test_no_vars_emits_nothing(dbt_available):
    """Full build is unchanged: with no vars both macros render to empty string."""
    rc, compiled, out = _compile_inline(
        "select 1 where 1=1 {{ period_filter() }}{{ scope_filter() }}"
    )
    assert rc == 0, out
    assert compiled.replace(" ", "") == "select1where1=1", compiled


def test_group_expands_to_descendants(dbt_available):
    """A GROUP code resolves against the hierarchy and expands via path patterns."""
    rc, compiled, out = _compile_inline(
        "select 1 where 1=1 {{ scope_filter() }}",
        dbt_vars="{entity_scope: GROUP_CORP}",
    )
    assert rc == 0, out
    assert "gold_consolidation_hierarchy" in compiled
    assert "consolidation_group = 'GROUP_CORP'" in compiled
    # The `_` metacharacter must be escaped in LIKE patterns (doubled in literal).
    assert r"like 'GROUP\\_CORP/%'" in compiled, compiled
    # ClickHouse has no ESCAPE clause — it must NOT be emitted.
    assert "escape" not in compiled.lower(), compiled


def test_period_filter_full(dbt_available):
    rc, compiled, out = _compile_inline(
        "select 1 where 1=1 {{ period_filter() }}",
        dbt_vars="{fiscal_year: 2024, fiscal_period: 3}",
    )
    assert rc == 0, out
    assert "fiscal_year = 2024" in compiled
    assert "fiscal_period = 3" in compiled


def test_period_filter_year_only(dbt_available):
    """include_period=false keeps the year predicate but drops the single period."""
    rc, compiled, out = _compile_inline(
        "select 1 where 1=1 {{ period_filter(include_period=false) }}",
        dbt_vars="{fiscal_year: 2024, fiscal_period: 3}",
    )
    assert rc == 0, out
    assert "fiscal_year = 2024" in compiled
    assert "fiscal_period" not in compiled


def test_period_filter_rejects_non_integer(dbt_available):
    """A non-numeric period var must fail loudly, not silently coerce to 0."""
    rc, compiled, out = _compile_inline(
        "select 1 where 1=1 {{ period_filter() }}",
        dbt_vars="{fiscal_period: notanumber}",
    )
    assert rc != 0, f"expected compile failure, got rc=0\n{out}"
    assert "must be a non-negative integer" in out, out


def test_like_escaping_matches_descendants_not_wildcards(ch):
    """Prove the generated LIKE pattern matches real descendants but treats the
    `_` in the group code literally (no wildcard over-selection)."""
    pat = r"GROUP\\_CORP/%"  # exactly what scope_filter emits into the SQL literal
    rows = ch(
        "SELECT "
        "['GROUP_CORP/DEMF','GROUP_CORP/GROUP_EMEA/DEMF','GROUPXCORP/DEMF','GROUP_CORP'] "
        "AS p, arrayMap(x -> x LIKE '" + pat + "', p) AS m FORMAT TSVRaw"
    )
    # child=1, grandchild=1, literal-underscore-mismatch=0, no-trailing=0
    assert rows.split("\t")[-1].strip() in ("[1,1,0,0]", "[1, 1, 0, 0]"), rows
