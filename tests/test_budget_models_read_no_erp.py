"""konsol#348 S3 (B1, QB1 b): the budget and variance models read no ERP.

The budget enters the warehouse through konsol only: epm_gold.budget_annual_input
(Budget Annual Input) and epm_raw.budget_entries (Budget Entry). The ERP budget
path (stg_*budget* -> bronze_budget_* -> silver_budget_entries -> the 'BUDGET'
branch of gold_scenario_trial_balance) held 0 rows on every stack and is
removed. This guard fails when it, or any ERP staging model, comes back under
one of the budget or variance models.

Walks ref() and source() transitively from each START model over
dbt_project/models. None may reach:

  - a `stg_*` model (an ERP adapter or the canonical union over them);
  - a `bronze_*` model, except bronze_trial_balance_submissions: that is the
    trial-balance upload (konsolidat#199), the one intake gold_trial_balance
    and so the actuals side of every variance read; it is not an ERP;
  - silver_budget_entries;
  - a source in d365_raw or erpnext_raw.

Plain unittest, static source, no third-party imports.
`python -m unittest -v tests.test_budget_models_read_no_erp`
"""
import os
import re
import unittest

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODELS = os.path.join(PROJECT_ROOT, "dbt_project", "models")

START = (
    "gold_spread_budget",
    "gold_scenario_trial_balance",
    "gold_variance_analysis",
    "gold_variance_ytd",
    "gold_variance_quarterly",
    "gold_budget_at_hierarchy_node",
    "gold_variance_at_hierarchy_node",
)
ALLOWED_BRONZE = {"bronze_trial_balance_submissions"}
FORBIDDEN_MODELS = {"silver_budget_entries"}
ERP_SOURCES = {"d365_raw", "erpnext_raw"}

REF = re.compile(r"ref\(\s*['\"]([^'\"]+)['\"]\s*\)")
SOURCE = re.compile(r"source\(\s*['\"]([^'\"]+)['\"]\s*,\s*['\"]([^'\"]+)['\"]\s*\)")


def _models():
    out = {}
    for dirpath, _dirs, files in os.walk(MODELS):
        for name in files:
            if name.endswith(".sql"):
                with open(os.path.join(dirpath, name), errors="replace") as f:
                    out[name[:-4]] = f.read()
    return out


def _reach(models, start):
    """(models reached, sources reached) from `start`, `start` included."""
    seen, sources, todo = set(), set(), [start]
    while todo:
        m = todo.pop()
        if m in seen:
            continue
        seen.add(m)
        sql = models.get(m, "")
        todo.extend(REF.findall(sql))
        sources.update(f"{s}.{t}" for s, t in SOURCE.findall(sql))
    return seen, sources


def _is_erp(model):
    if model.startswith("stg_"):
        return True
    if model.startswith("bronze_") and model not in ALLOWED_BRONZE:
        return True
    return model in FORBIDDEN_MODELS


class BudgetModelsReadNoErp(unittest.TestCase):
    def setUp(self):
        self.models = _models()

    def test_start_models_exist(self):
        missing = [m for m in START if m not in self.models]
        self.assertEqual(missing, [], f"START models not found under {MODELS}: {missing}")

    def test_no_start_model_reaches_an_erp_model(self):
        hits = {}
        for start in START:
            reached, _ = _reach(self.models, start)
            erp = sorted(m for m in reached if _is_erp(m))
            if erp:
                hits[start] = erp
        self.assertEqual(
            hits, {}, f"budget/variance models reach ERP models (stg_*, bronze_*, silver_budget_entries): {hits}"
        )

    def test_no_start_model_reaches_an_erp_source(self):
        hits = {}
        for start in START:
            _, sources = _reach(self.models, start)
            erp = sorted(s for s in sources if s.split(".")[0] in ERP_SOURCES)
            if erp:
                hits[start] = erp
        self.assertEqual(hits, {}, f"budget/variance models reach ERP sources: {hits}")


if __name__ == "__main__":
    unittest.main()
