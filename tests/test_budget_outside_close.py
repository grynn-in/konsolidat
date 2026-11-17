"""konsol#348 S4 (W7; BUD-11-3, S4-Q3 a): the budget stays outside the close.

The close fingerprint konsol stamps on a Close Run hashes ONE relation,
epm_gold.gold_fully_consolidated_tb (konsol/close/fingerprint.py, NUMBERS_SQL),
so a consolidated budget build must never change that table, and the budget
models must never be rebuilt by the close. Both directions are pinned here as a
static walk over dbt_project/models, like test_budget_models_read_no_erp:

  - gold_fully_consolidated_tb, and every model it reaches through ref(),
    reads no budget model (gold_consolidated_budget_tb,
    gold_fully_consolidated_budget, gold_spread_budget) and no budget source
    (epm_raw.budget_entries, epm_gold.budget_annual_input,
    epm_staging.budget_cycles). A budget approved after a close therefore
    cannot void its signature (BUD-11-1 by construction).
  - the two consolidated budget models reach neither gold_fully_consolidated_tb
    nor gold_consolidated_trial_balance: a budget is translated at its Cycle's
    Rate Set from its own fact, never derived from the actuals' consolidation.
  - gold_fully_consolidated_budget reads gold_consolidated_budget_tb (the
    FCTB-shaped model is a projection of the CTB-shaped one, S4-Q3 a).
  - the gold yml documents both budget models as BEFORE ELIMINATIONS, naming
    konsol#427 (no partner, no ic_elimination) and konsol#425 (no deal
    journals, topside or equity method), so a reader meets the limit where the
    model is described, not only in its header.

Plain unittest, static source, no third-party imports.
`python -m unittest -v tests.test_budget_outside_close`
"""
import os
import re
import unittest

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODELS = os.path.join(PROJECT_ROOT, "dbt_project", "models")
GOLD_YML = os.path.join(MODELS, "gold", "_gold__models.yml")

CLOSE_ROOT = "gold_fully_consolidated_tb"
ACTUALS_CONSOLIDATION = {"gold_fully_consolidated_tb", "gold_consolidated_trial_balance"}
BUDGET_MODELS = ("gold_consolidated_budget_tb", "gold_fully_consolidated_budget")
BUDGET_FACT_MODELS = {"gold_spread_budget", "gold_budget_entity_ownership"}
BUDGET_SOURCES = {
    "epm_raw.budget_entries",
    "epm_gold.budget_annual_input",
    "epm_staging.budget_cycles",
    # konsol#348 S6 pair A: the declared current round of a forecast
    "epm_staging.current_forecasts",
}
# konsol#348 S6 pair A (S6-Q1 b, S6-Q2 a): the forecast rounds' relations. The
# close fingerprint's table must reach none of them, and each must exist.
FORECAST_MODELS = (
    "gold_forecast_current_round",
    "gold_forecast_current",
    "gold_forecast_current_at_hierarchy_node",
    "gold_latest_estimate",
    "gold_latest_estimate_current",
)
# Each budget model's yml description must name both limits, so the reader of
# the catalogue meets them without opening the SQL.
LIMIT_MARKERS = ("before eliminations", "konsol#427", "konsol#425")

REF = re.compile(r"ref\(\s*['\"]([^'\"]+)['\"]\s*\)")
SOURCE = re.compile(r"source\(\s*['\"]([^'\"]+)['\"]\s*,\s*['\"]([^'\"]+)['\"]\s*\)")
YML_MODEL = re.compile(r"^  - name:\s*(\S+)\s*$")


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


def _yml_descriptions(path):
    """model name -> the text of its entry (up to the next top-level model)."""
    out, current, buf = {}, None, []
    with open(path, errors="replace") as f:
        for line in f:
            m = YML_MODEL.match(line)
            if m:
                if current:
                    out[current] = "".join(buf)
                current, buf = m.group(1), []
            elif current:
                buf.append(line)
    if current:
        out[current] = "".join(buf)
    return out


class BudgetOutsideClose(unittest.TestCase):
    def setUp(self):
        self.models = _models()

    def test_models_exist(self):
        missing = [m for m in (CLOSE_ROOT,) + BUDGET_MODELS + FORECAST_MODELS if m not in self.models]
        self.assertEqual(missing, [], f"models not found under {MODELS}: {missing}")

    def test_the_close_table_reads_no_budget_model_or_source(self):
        reached, sources = _reach(self.models, CLOSE_ROOT)
        budget_hits = sorted(reached & (set(BUDGET_MODELS) | BUDGET_FACT_MODELS | set(FORECAST_MODELS)))
        source_hits = sorted(sources & BUDGET_SOURCES)
        self.assertEqual(
            budget_hits, [],
            f"{CLOSE_ROOT} (the close fingerprint's one relation) reaches budget models: {budget_hits}",
        )
        self.assertEqual(
            source_hits, [],
            f"{CLOSE_ROOT} (the close fingerprint's one relation) reaches budget sources: {source_hits}",
        )

    def test_the_budget_models_read_no_actuals_consolidation(self):
        hits = {}
        for start in BUDGET_MODELS:
            reached, _ = _reach(self.models, start)
            actuals = sorted(reached & ACTUALS_CONSOLIDATION)
            if actuals:
                hits[start] = actuals
        self.assertEqual(
            hits, {},
            f"budget models reach the actuals' consolidation (a budget is translated from its own fact): {hits}",
        )

    def test_the_fctb_shaped_budget_is_a_projection_of_the_ctb_shaped_one(self):
        refs = set(REF.findall(self.models.get("gold_fully_consolidated_budget", "")))
        self.assertIn("gold_consolidated_budget_tb", refs)

    def test_both_budget_models_are_documented_before_eliminations(self):
        entries = _yml_descriptions(GOLD_YML)
        problems = {}
        for model in BUDGET_MODELS:
            text = entries.get(model, "").lower()
            if not text:
                problems[model] = "no entry in _gold__models.yml"
                continue
            missing = [m for m in LIMIT_MARKERS if m.lower() not in text]
            if missing:
                problems[model] = f"yml entry does not name {missing}"
        self.assertEqual(problems, {}, f"budget models' yml entries: {problems}")


if __name__ == "__main__":
    unittest.main()
