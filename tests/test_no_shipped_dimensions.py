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
2. a canonical staging model names a `dim_<name>` column outside a comment.
   Macro names (`dim_select`, `dim_harmonize_joins`, ...) are machinery, not
   dimensions, and are allowed.

Test fixtures are not shipped. They declare the dimensions they need in the
harness (`FIXTURE_DIMENSIONS`, scripts/tb_only_first_build.py), and the two
scripts that build at declared dimensions must pass that declaration, or the
project would build at the empty default and the dimensional fixtures would
lose their columns:

3. scripts/ci_full_build.py and scripts/fixture_gate.py pass
   `fixture_dimension_vars()` to dbt.

Plain unittest, static source, no third-party imports.
`python -m unittest -v tests.test_no_shipped_dimensions`
"""
import glob
import os
import re
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJECT_YML = os.path.join(ROOT, "dbt_project", "dbt_project.yml")
CANONICAL = os.path.join(ROOT, "dbt_project", "models", "staging", "canonical")
MACROS = os.path.join(ROOT, "dbt_project", "macros")
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


class CanonicalUnionNamesNoDimension(unittest.TestCase):
    def test_canonical_models_name_no_dimension_column(self):
        macros = _macro_names()
        found = {}
        for path in sorted(glob.glob(os.path.join(CANONICAL, "*.sql"))):
            names = set(DIM_RE.findall(_strip_comments(_read(path)))) - macros
            if names:
                found[os.path.basename(path)] = sorted(names)
        self.assertEqual(found, {}, "canonical staging selects dimensions by name; "
                                    "render them from var('dimensions') instead")


class FixtureBuildsDeclareTheirDimensions(unittest.TestCase):
    def test_both_scripts_pass_the_fixture_declaration(self):
        for name in ("ci_full_build.py", "fixture_gate.py"):
            src = _read(os.path.join(ROOT, "scripts", name))
            self.assertTrue("fixture_dimension_vars()" in src,
                            f"scripts/{name} does not pass fixture_dimension_vars() to dbt")


if __name__ == "__main__":
    unittest.main()
