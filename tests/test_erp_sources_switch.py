"""Bronze models build without D365 (konsolidat#207).

A bronze model that reads a D365 F&O staging model (`ref('stg_d365_fo__...')`)
does so only inside the `erp_sources` guard. Its `{% else %}` branch returns
`empty_relation(...)` (macros/erp_sources.sql) with the same columns and
types, so a site whose only source is the trial-balance upload still builds.
"""
import os
import re

import pytest

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BRONZE = os.path.join(PROJECT_ROOT, "dbt_project", "models", "bronze")

GUARD = "{% if 'd365_fo' in var('erp_sources', []) %}"
ELSE = re.compile(r"{%-?\s*else\s*-?%}")
ENDIF = re.compile(r"{%-?\s*endif\s*-?%}")
D365_REF = re.compile(r"ref\(\s*['\"]stg_d365_fo__")

GUARDED = [
    "bronze_budget_register_entries",
    "bronze_budget_transaction_lines",
    "bronze_consolidation_account_groups",
    "bronze_exchange_rate_types",
]


def _read(model):
    with open(os.path.join(BRONZE, model + ".sql")) as f:
        return f.read()


@pytest.mark.parametrize("model", GUARDED)
def test_d365_ref_inside_erp_sources_guard(model):
    sql = _read(model)
    refs = [m.start() for m in D365_REF.finditer(sql)]
    assert refs, f"{model} reads no stg_d365_fo__ model"
    g = sql.find(GUARD)
    assert g >= 0, f"{model} has no guard {GUARD}"
    else_m = ELSE.search(sql, g)
    assert else_m, f"{model}: guard has no {{% else %}} branch"
    endif_m = ENDIF.search(sql, else_m.end())
    assert endif_m, f"{model}: guard has no {{% endif %}}"
    outside = [p for p in refs if not (g < p < else_m.start())]
    assert not outside, f"{model}: {len(outside)} stg_d365_fo__ ref(s) outside the guard"
    assert "empty_relation(" in sql[else_m.end():endif_m.start()], (
        f"{model}: the else branch must return empty_relation(...)"
    )
