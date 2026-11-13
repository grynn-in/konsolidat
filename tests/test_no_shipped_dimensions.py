"""konsol#287: konsolidat ships no dimensions.

Decided by Deepak Pai, 17 Sep 2026: konsol ships no Dimensions; each site
declares its own. konsol writes the site's declaration into the konsol-managed
block of dbt_project.yml. What the repository carries in that block is
therefore the default for any build konsol has not yet configured: a fresh
stack, a CI job, a scratch copy. Until konsol#287 it named three dimensions
(business unit, cost centre, department) that encoded one customer's chart,
and the canonical ERP union selected the same three by name.

This guard fails when either comes back:

1. the shipped `dimensions` default declares any dimension;
2. a model, macro or singular test names a `dim_<name>` column outside a
   comment. Macro names (`dim_select`, `dim_harmonize_joins`, ...) are
   machinery, not dimensions, and are allowed. The ERP staging trees
   (models/staging/d365_fo, models/staging/erpnext) are excluded: they read
   the ERP's own columns and are being removed (konsolidat#221). Two singular
   tests are listed as deferred to konsol#348 S2 (DEFERRED below), each with
   its reason; any other hit fails.

Test fixtures are not shipped. They declare the dimensions they need in the
harness (`FIXTURE_DIMENSIONS`, scripts/tb_only_first_build.py), and the two
scripts that build at declared dimensions must pass that declaration, or the
project would build at the empty default and the dimensional fixtures would
lose their columns:

3. every script that runs dbt against fixture-built tables CALLS
   `fixture_dimension_vars()` (found in the parsed source, so a comment or a
   string naming it does not count): scripts/ci_full_build.py,
   scripts/fixture_gate.py, tests/integration/conftest.py and
   tests/integration/test_orchestrator_filters.py. The integration suite runs
   on the tables ci_full_build.py's first leg built, so a dbt call there at the
   empty default would build on top of them at another shape.

Plain unittest, static source, no third-party imports.
`python -m unittest -v tests.test_no_shipped_dimensions`
"""
import ast
import glob
import os
import re
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJECT_YML = os.path.join(ROOT, "dbt_project", "dbt_project.yml")
MACROS = os.path.join(ROOT, "dbt_project", "macros")
SCANNED = [os.path.join(ROOT, "dbt_project", d) for d in ("models", "macros", "tests")]
EXCLUDED_TREES = [os.path.join(ROOT, "dbt_project", "models", "staging", erp) + os.sep
                  for erp in ("d365_fo", "erpnext")]
#: Known hits, deferred to konsol#348 S2, which re-points the fixtures to ZZ
#: dimension names. Both are singular tests over the hierarchy_dated.sql fixture,
#: whose ZZ_DIV / ZZ_DIV_CC trees are built over these dimensions. Each renders
#: nothing when the site does not declare the dimension it reads, so neither
#: ships a dimension into a site's build; they are fixture assertions that name
#: the fixture's own columns. A new hit, or a new name in these files, fails.
DEFERRED = {
    "tests/assert_hierarchy_node_as_of.sql": ["dim_business_unit", "dim_cost_center"],
    "tests/assert_unassigned_as_of.sql": ["dim_business_unit"],
}
#: The scripts that run dbt against tables built at FIXTURE_DIMENSIONS.
FIXTURE_DBT_CALLERS = (
    "scripts/ci_full_build.py",
    "scripts/fixture_gate.py",
    "tests/integration/conftest.py",
    "tests/integration/test_orchestrator_filters.py",
)
MANAGED_BEGIN = "# --- BEGIN konsol-managed vars"
MANAGED_END = "# --- END konsol-managed vars ---"
DIM_RE = re.compile(r"\bdim_[a-z0-9_]+")


def _read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def _strip_comments(sql):
    sql = re.sub(r"\{#.*?#\}", "", sql, flags=re.S)
    return re.sub(r"--[^\n]*", "", sql)


def _macro_names():
    names = set()
    for path in glob.glob(os.path.join(MACROS, "**", "*.sql"), recursive=True):
        names |= set(re.findall(r"\{%-?\s*macro\s+(\w+)", _read(path)))
    return names


class ShippedDefaultDeclaresNoDimension(unittest.TestCase):
    def test_the_managed_dimensions_default_is_empty(self):
        text = _read(PROJECT_YML)
        block = text.split(MANAGED_BEGIN, 1)[1].split(MANAGED_END, 1)[0]
        m = re.search(r"^  dimensions:(.*?)(?=^  [a-z_]+:)", block, re.S | re.M)
        self.assertIsNotNone(m, "no `dimensions:` key in the konsol-managed vars block")
        self.assertEqual(
            m.group(1).strip(), "[]",
            "dbt_project.yml ships a dimension in its konsol-managed default; a site "
            "declares its own (konsol#287, decided 17 Sep 2026)")


def _calls(path, name):
    """Calls to ``name`` in the parsed source: comments and strings do not count."""
    tree = ast.parse(_read(path), filename=path)
    return [n for n in ast.walk(tree) if isinstance(n, ast.Call)
            and ((isinstance(n.func, ast.Name) and n.func.id == name)
                 or (isinstance(n.func, ast.Attribute) and n.func.attr == name))]


class ProjectNamesNoDimension(unittest.TestCase):
    def test_models_macros_and_tests_name_no_dimension_column(self):
        macros = _macro_names()
        found = {}
        for base in SCANNED:
            for path in sorted(glob.glob(os.path.join(base, "**", "*.sql"), recursive=True)):
                if any(path.startswith(t) for t in EXCLUDED_TREES):
                    continue
                names = set(DIM_RE.findall(_strip_comments(_read(path)))) - macros
                if names:
                    rel = os.path.relpath(path, os.path.join(ROOT, "dbt_project"))
                    found[rel] = sorted(names)
        self.assertEqual(found, DEFERRED,
                         "a model, macro or test selects a dimension by name; render it "
                         "from var('dimensions') instead (DEFERRED lists the known hits)")


class FixtureBuildsDeclareTheirDimensions(unittest.TestCase):
    def test_every_fixture_dbt_caller_calls_the_fixture_declaration(self):
        for rel in FIXTURE_DBT_CALLERS:
            with self.subTest(script=rel):
                self.assertTrue(_calls(os.path.join(ROOT, rel), "fixture_dimension_vars"),
                                f"{rel} does not call fixture_dimension_vars()")

    def test_a_comment_or_string_does_not_count(self):
        import tempfile
        with tempfile.NamedTemporaryFile("w", suffix=".py", delete=False) as f:
            f.write("# fixture_dimension_vars()\nX = 'fixture_dimension_vars()'\n")
        try:
            self.assertEqual(_calls(f.name, "fixture_dimension_vars"), [])
        finally:
            os.unlink(f.name)


if __name__ == "__main__":
    unittest.main()
