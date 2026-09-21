"""The gold-domain guard must look at the models on disk, not only at the YAML.

`scripts/check_gold_domains.py` exists, in its own words, so that "a model added
to dbt_project.yml without a domain fails CI instead of disappearing from
governed builds" — because a gold model with no `domain:` tag "is built by NO
scope (only a full build), so it silently goes stale".

It enumerated the **YAML**. A gold model that was never registered as a konsol
Build Model doc does not appear in the generated block at all, so the guard
could not see it, and it passed. Five had accumulated:

    gold_cash_flow_indirect          gold_consolidated_cash_flow
    gold_cashflow_fact               gold_consolidated_fact
    gold_unmapped_dimension_values

Each one is a real model on disk that no scoped build ever rebuilds. The guard
that was supposed to make this impossible was blind to exactly the case it
described — a check that could not fail.

These tests drive the guard against fixture directories rather than the live
project, so they keep working as the real model list changes.

Needs pyyaml, so it runs in the gold-domain-coverage job (which installs it)
rather than in contract-tests.

`python -m unittest -v tests.test_gold_domain_coverage`
"""
import os
import shutil
import sys
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "scripts"))

import check_gold_domains  # noqa: E402


def _project(tmp, listed, on_disk):
    """A throwaway dbt project: `listed` in the YAML, `on_disk` as .sql files."""
    proj = os.path.join(tmp, "dbt_project")
    os.makedirs(os.path.join(proj, "models", "gold"), exist_ok=True)
    lines = ["models:", "  open_epm:", "    gold:"]
    for model, domain in listed.items():
        lines.append(f"      {model}:")
        tags = "['gold'" + (f", 'domain:{domain}'" if domain else "") + "]"
        lines.append(f"        +tags: {tags}")
    with open(os.path.join(proj, "dbt_project.yml"), "w") as f:
        f.write("\n".join(lines) + "\n")
    for model in on_disk:
        with open(os.path.join(proj, "models", "gold", model + ".sql"), "w") as f:
            f.write("select 1\n")
    return os.path.join(proj, "dbt_project.yml")


class GuardSeesTheDirectory(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp)

    def test_a_model_on_disk_but_absent_from_the_yaml_fails(self):
        """The blind spot: never registered, so never in the YAML, so invisible."""
        path = _project(self.tmp,
                        listed={"gold_a": "actuals"},
                        on_disk=["gold_a", "gold_orphan"])
        self.assertEqual(check_gold_domains.check(path), 1,
                         "an unregistered gold model passed the guard")

    def test_the_failure_names_the_model(self):
        path = _project(self.tmp,
                        listed={"gold_a": "actuals"},
                        on_disk=["gold_a", "gold_orphan"])
        import io
        from contextlib import redirect_stdout
        buf = io.StringIO()
        with redirect_stdout(buf):
            check_gold_domains.check(path)
        self.assertIn("gold_orphan", buf.getvalue())

    def test_everything_registered_and_tagged_passes(self):
        path = _project(self.tmp,
                        listed={"gold_a": "actuals", "gold_b": "consolidation"},
                        on_disk=["gold_a", "gold_b"])
        self.assertEqual(check_gold_domains.check(path), 0)

    def test_a_listed_model_with_no_domain_still_fails(self):
        """The case the guard already caught — it must keep catching it."""
        path = _project(self.tmp,
                        listed={"gold_a": "actuals", "gold_b": None},
                        on_disk=["gold_a", "gold_b"])
        self.assertEqual(check_gold_domains.check(path), 1)

    def test_an_unknown_domain_still_fails(self):
        path = _project(self.tmp, listed={"gold_a": "not_a_domain"}, on_disk=["gold_a"])
        self.assertEqual(check_gold_domains.check(path), 1)

    def test_a_model_in_the_yaml_with_no_file_fails(self):
        """The other direction: a stale entry for a model that was deleted, which
        makes the count reassuring and wrong."""
        path = _project(self.tmp,
                        listed={"gold_a": "actuals", "gold_deleted": "actuals"},
                        on_disk=["gold_a"])
        self.assertEqual(check_gold_domains.check(path), 1)


class TheRealProjectIsClean(unittest.TestCase):
    """And the live project must pass — this is what the five fixes are for."""

    def test_every_gold_model_in_this_repo_has_a_domain(self):
        path = os.path.join(ROOT, "dbt_project", "dbt_project.yml")
        self.assertEqual(check_gold_domains.check(path), 0)


if __name__ == "__main__":
    unittest.main()
