"""konsol#348 S5 (W1): the contract konsol's readers of the budget warehouse rely on.

konsol's Consolidated Statement (S5) reads two warehouse tables by column name:

  - epm_gold.gold_fully_consolidated_budget: consolidation_group, data_area_id,
    fiscal_year, fiscal_period, main_account, adjustment_type, amount,
    scenario_id, cycle, layer, reporting_currency; the two plug rows by the
    literals main_account 'UNBALANCED' and 'CTA'; the four adjustment_type
    values entity, unbalanced, cta, nci_attribution.
  - epm_gold.gold_consolidated_budget_tb: data_area_id, main_account,
    scenario_id, cycle, layer, translation_rate, rate_set.

Pinned here as static text, like test_budget_outside_close: the model SQL, the
consolidation_core macro that supplies the columns the budget model selects with
`select *` (data_area_id, translation_rate), and _gold__models.yml, whose model
descriptions carry the note that konsol reads them. Renaming or dropping any of
these breaks the reader in konsol, so it must break this test first.

Not pinned: fx_method. gold_consolidated_budget_tb drops it (`select * except
(... fx_method ...)`), so a reader cannot rely on it; see the PR notes.

Plain unittest, static source, no third-party imports.
`python -m unittest -v tests.test_fully_consolidated_budget_contract`
"""
import os
import re
import unittest

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DBT = os.path.join(PROJECT_ROOT, "dbt_project")
GOLD = os.path.join(DBT, "models", "gold")
FCB_SQL = os.path.join(GOLD, "gold_fully_consolidated_budget.sql")
CBT_SQL = os.path.join(GOLD, "gold_consolidated_budget_tb.sql")
CORE_SQL = os.path.join(DBT, "macros", "consolidation_core.sql")
GOLD_YML = os.path.join(GOLD, "_gold__models.yml")

FCB = "gold_fully_consolidated_budget"
CBT = "gold_consolidated_budget_tb"

FCB_COLUMNS = (
    "consolidation_group", "data_area_id", "fiscal_year", "fiscal_period",
    "main_account", "adjustment_type", "amount", "scenario_id", "cycle",
    "layer", "reporting_currency",
)
ADJUSTMENT_TYPES = ("entity", "unbalanced", "cta", "nci_attribution")
PLUG_ACCOUNTS = ("UNBALANCED", "CTA")
CBT_SQL_COLUMNS = ("main_account", "scenario_id", "cycle", "layer", "rate_set")
# Supplied by the core through the budget model's `select *`.
CBT_CORE_COLUMNS = ("data_area_id", "main_account", "translation_rate")
# Documented in the yml entry of each model (column `- name:` lines).
YML_COLUMNS = {
    FCB: ("consolidation_group", "data_area_id", "scenario_id", "cycle", "layer",
          "adjustment_type", "amount"),
    CBT: ("consolidation_group", "data_area_id", "scenario_id", "cycle", "layer", "rate_set"),
}
NOTE = "read by konsol's Consolidated Statement (S5)"

YML_MODEL = re.compile(r"^  - name:\s*(\S+)\s*$")


def _read(path):
    with open(path, errors="replace") as f:
        return f.read()


def _word(text, name):
    return re.search(r"(?<![A-Za-z0-9_])" + re.escape(name) + r"(?![A-Za-z0-9_])", text) is not None


def _yml_entries(path):
    out, current, buf = {}, None, []
    for line in _read(path).splitlines(keepends=True):
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


class FullyConsolidatedBudgetSql(unittest.TestCase):
    def setUp(self):
        self.sql = _read(FCB_SQL)

    def test_names_the_columns_konsol_reads(self):
        missing = [c for c in FCB_COLUMNS if not _word(self.sql, c)]
        self.assertEqual(missing, [], f"{FCB}.sql no longer names: {missing}")

    def test_plug_rows_carry_their_literal_main_account(self):
        for lit in PLUG_ACCOUNTS:
            self.assertRegex(
                self.sql, r"'%s'\s+as\s+main_account\b" % lit,
                f"{FCB}.sql lost the literal main_account '{lit}'",
            )

    def test_the_four_adjustment_types_are_emitted(self):
        for t in ADJUSTMENT_TYPES:
            self.assertRegex(
                self.sql, r"'%s'\s+as\s+adjustment_type\b" % t,
                f"{FCB}.sql no longer emits adjustment_type '{t}'",
            )

    def test_no_other_adjustment_type_is_emitted(self):
        found = set(re.findall(r"'([a-z_]+)'\s+as\s+adjustment_type\b", self.sql))
        self.assertEqual(found, set(ADJUSTMENT_TYPES), f"adjustment_type literals: {sorted(found)}")


class ConsolidatedBudgetTbSql(unittest.TestCase):
    def test_names_the_grain_and_rate_set_columns(self):
        sql = _read(CBT_SQL)
        missing = [c for c in CBT_SQL_COLUMNS if not _word(sql, c)]
        self.assertEqual(missing, [], f"{CBT}.sql no longer names: {missing}")

    def test_keeps_the_columns_the_core_supplies(self):
        sql = _read(CBT_SQL)
        self.assertIn("consolidation_core(", sql, f"{CBT}.sql no longer builds on consolidation_core")
        for c in CBT_CORE_COLUMNS:
            self.assertFalse(
                re.search(r"except\s*\([^)]*(?<![A-Za-z0-9_])%s(?![A-Za-z0-9_])" % c, sql),
                f"{CBT}.sql drops {c} with `except (...)`",
            )
        core = _read(CORE_SQL)
        for c in CBT_CORE_COLUMNS:
            self.assertTrue(_word(core, c), f"consolidation_core no longer produces {c}")
        self.assertRegex(core, r"end\s+as\s+translation_rate\b")


class GoldYml(unittest.TestCase):
    def setUp(self):
        self.entries = _yml_entries(GOLD_YML)

    def test_both_models_are_documented_with_their_columns(self):
        for model, cols in YML_COLUMNS.items():
            entry = self.entries.get(model)
            self.assertIsNotNone(entry, f"{model} has no entry in _gold__models.yml")
            missing = [c for c in cols if not re.search(r"^\s+- name:\s*%s\s*$" % c, entry, re.M)]
            self.assertEqual(missing, [], f"{model}: columns not documented in the yml: {missing}")

    def test_descriptions_note_that_konsol_reads_them(self):
        for model in (FCB, CBT):
            # The model description only: the text before the `columns:` key.
            entry = " ".join(self.entries.get(model, "").split("\n    columns:")[0].split())
            self.assertIn(NOTE, entry, f"{model}: the yml description lacks the note '{NOTE}'")


if __name__ == "__main__":
    unittest.main()
