"""konsol#287 review: no silent reshape of a site's dimension columns.

dbt_project.yml ships `dimensions: []`, and konsol writes a site's declaration
over it on migrate. A build that runs before that migrate (a stack that pulled
the new file and was not migrated, or a hand-run `dbt build` on a fresh copy)
would rebuild every dimensional model at the empty default and drop the site's
dim_* columns without a word. The on-run-start guard
`assert_dimensions_match_built()` refuses a `run` or `build` whose
`var('dimensions')` differs from the dim_* columns gold_trial_balance already
has, unless the table does not exist yet or `--full-refresh` asks for the
rebuild.

Each case runs dbt on a copy of the project under a scratch prefix
(scripts/tb_only_first_build.py copy_project), so nothing named epm_* is read
or written, and judges the guard by its own hook line: the selected model may
fail on the empty scratch sources, which this test does not care about.

Run with: pytest tests/integration/test_dimension_shape_guard.py -v
"""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "scripts"))
from tb_only_first_build import LAYERS, copy_project  # noqa: E402

PREFIX = "zzdg"
DBS = [PREFIX] + [f"{PREFIX}_{layer}" for layer in LAYERS]
TB = f"{PREFIX}_gold.gold_trial_balance"
REFUSED = "refusing to reshape the dimension columns"
HOOK_OK = re.compile(r"\bOK hook: open_epm\.on-run-start\.\d+")


def _dims(*names):
    return {"dimensions": [{"name": n, "source_column": n, "label": n, "cube_type": "string",
                            "in_budget": False} for n in names]}


@pytest.fixture(scope="module")
def project(ch):
    if shutil.which("dbt") is None:
        pytest.skip("dbt not on PATH")
    for db in DBS:
        ch(f"DROP DATABASE IF EXISTS {db}")
        ch(f"CREATE DATABASE {db}")
    work = tempfile.mkdtemp(prefix="dim_guard_")
    path = os.path.join(work, "dbt_project")
    copy_project(PREFIX, path)
    yield path
    for db in DBS:
        ch(f"DROP DATABASE IF EXISTS {db}")
    shutil.rmtree(work, ignore_errors=True)


def _dbt(project, command, dbt_vars, *extra):
    cmd = ["dbt", "--no-use-colors", command, "--select", "silver_main_accounts",
           "--vars", json.dumps(dbt_vars), *extra,
           "--project-dir", project, "--profiles-dir", project]
    proc = subprocess.run(cmd, cwd=project, capture_output=True, text=True, timeout=600)
    return (proc.stdout or "") + (proc.stderr or "")


def _guard_hook_ran(out):
    """Every on-run-start hook passed, the guard among them, and it refused nothing."""
    return REFUSED not in out and len(HOOK_OK.findall(out)) >= 1 and "ERROR hook" not in out


def _make_tb(ch, *dim_names):
    ch(f"DROP TABLE IF EXISTS {TB}")
    cols = "".join(f", {n} String" for n in dim_names)
    ch(f"CREATE TABLE {TB} (data_area_id String{cols}) ENGINE = MergeTree ORDER BY tuple()")


def test_a_fresh_schema_builds_at_any_declaration(ch, project):
    ch(f"DROP TABLE IF EXISTS {TB}")
    out = _dbt(project, "run", _dims())
    assert _guard_hook_ran(out), out[-3000:]


def test_a_matching_declaration_builds(ch, project):
    _make_tb(ch, "dim_zz_a", "dim_zz_b")
    out = _dbt(project, "run", _dims("dim_zz_b", "dim_zz_a"))
    assert _guard_hook_ran(out), out[-3000:]


def test_a_different_declaration_is_refused_naming_both_lists_and_the_fix(ch, project):
    _make_tb(ch, "dim_zz_a", "dim_zz_b")
    out = _dbt(project, "build", _dims())
    assert REFUSED in out, out[-3000:]
    assert "dim_zz_a, dim_zz_b" in out and "(none)" in out, out[-3000:]
    assert "konsol migrate" in out and "--full-refresh" in out, out[-3000:]
    assert "full-refresh Build Approval is pending: approve it (or wait for it) instead of migrating" \
        in out, out[-3000:]
    # the run stopped at the hook: the table keeps its columns
    cols = ch(f"select arrayStringConcat(groupArray(name), ',') from system.columns "
              f"where database = '{PREFIX}_gold' and table = 'gold_trial_balance'")
    assert cols == "data_area_id,dim_zz_a,dim_zz_b"


def test_full_refresh_rebuilds_deliberately(ch, project):
    _make_tb(ch, "dim_zz_a", "dim_zz_b")
    out = _dbt(project, "run", _dims(), "--full-refresh")
    assert _guard_hook_ran(out), out[-3000:]


def test_dbt_test_reshapes_nothing_and_is_not_guarded(ch, project):
    _make_tb(ch, "dim_zz_a", "dim_zz_b")
    out = _dbt(project, "test", _dims())
    assert REFUSED not in out, out[-3000:]


def test_a_declared_budget_only_dimension_without_the_prefix_builds(ch, project):
    """var('dimensions') holds every Published Dimension, and one that is not in
    the trial balance may be named without dim_ (konsol dimension.py validate).
    gold_trial_balance selects every declared dimension (dim_select()), so the
    built table carries that column too: the guard must count it, not refuse."""
    _make_tb(ch, "business_unit", "dim_zz_a")
    out = _dbt(project, "run", _dims("dim_zz_a", "business_unit"))
    assert _guard_hook_ran(out), out[-3000:]


def test_a_built_non_dimension_column_does_not_refuse(ch, project):
    """A built column that is neither dim_* nor declared (here: a fixed column a
    later model change dropped) is not a dimension and must not refuse."""
    _make_tb(ch, "zz_dropped_fixed_column", "dim_zz_a")
    out = _dbt(project, "run", _dims("dim_zz_a"))
    assert _guard_hook_ran(out), out[-3000:]


def test_an_undeclared_built_non_dim_column_is_not_detected_by_design(ch, project):
    """Not detected, by design (konsol#348 BUD-8-2): every published budget
    dimension is also a trial-balance dimension, and those require dim_. So an
    undeclared non-dim_ column cannot come from a published dimension; the guard
    ignores it rather than keep a hand list of the model's fixed columns."""
    _make_tb(ch, "business_unit", "dim_zz_a")
    out = _dbt(project, "run", _dims("dim_zz_a"))
    assert _guard_hook_ran(out), out[-3000:]


def test_dbt_retry_is_guarded(ch, project):
    """`dbt retry` re-runs the previous run or build: it is checked too."""
    _make_tb(ch, "dim_zz_a", "dim_zz_b")
    # A build that passes the guard and leaves a failure to retry: this
    # singular test reads a staging table the scratch schema never creates.
    first = _dbt(project, "build", _dims("dim_zz_a", "dim_zz_b"), "--select",
                 "assert_historical_is_equity_only")
    assert _guard_hook_ran(first) and "historical_equity_rates" in first, first[-3000:]
    cmd = ["dbt", "--no-use-colors", "retry", "--vars", json.dumps(_dims()),
           "--project-dir", project, "--profiles-dir", project]
    proc = subprocess.run(cmd, cwd=project, capture_output=True, text=True, timeout=600)
    out = (proc.stdout or "") + (proc.stderr or "")
    assert REFUSED in out, out[-3000:]
