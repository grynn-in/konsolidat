"""Bronze models build without D365 (konsolidat#207).

A bronze model that reads a D365 F&O staging model (`ref('stg_d365_fo__...')`)
does so only inside the `erp_sources` guard. Its `{% else %}` branch returns
`empty_relation(...)` (macros/erp_sources.sql) with the same columns and
types, so a site whose only source is the trial-balance upload still builds.

Two bronze models read the CANONICAL union instead (`stg_gl_entries`,
`stg_budget_entries`), which is already empty and typed when `erp_sources` is
empty (row D4). They read it unconditionally: a `d365_fo` guard around it
would blank an ERPNext-only site's rows. Only their join to the D365 adapter
(for D365-only fields) sits inside the guard.
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
    "bronze_consolidation_account_groups",
    "bronze_exchange_rate_types",
    "bronze_financial_dimension_values",
    "bronze_financial_dimensions",
    "bronze_fiscal_calendar_years",
    "bronze_fiscal_calendars",
    "bronze_general_journal_entries",
    "bronze_main_account_categories",
]

# Bronze models over the canonical union: model -> the canonical model it reads.
CANONICAL_READERS = {
    "bronze_general_journal_account_entries": "stg_gl_entries",
    "bronze_budget_transaction_lines": "stg_budget_entries",
}

MODELS = os.path.join(PROJECT_ROOT, "dbt_project", "models")
SCANNED_LAYERS = ("bronze", "silver", "gold")


def _read(model):
    with open(os.path.join(BRONZE, model + ".sql")) as f:
        return f.read()


def _guarded_spans(sql):
    """(start, end) of every `if 'd365_fo' in erp_sources` branch, up to its
    else or endif, whichever comes first."""
    spans = []
    g = sql.find(GUARD)
    while g >= 0:
        ends = [m.start() for m in (ELSE.search(sql, g), ENDIF.search(sql, g)) if m]
        end = min(ends) if ends else g
        spans.append((g, end))
        g = sql.find(GUARD, g + len(GUARD))
    return spans


def _unguarded_d365_refs():
    found = []
    for layer in SCANNED_LAYERS:
        for dirpath, _, files in os.walk(os.path.join(MODELS, layer)):
            for name in sorted(files):
                if not name.endswith(".sql"):
                    continue
                path = os.path.join(dirpath, name)
                with open(path) as f:
                    sql = f.read()
                spans = _guarded_spans(sql)
                for m in D365_REF.finditer(sql):
                    if not any(s < m.start() < e for s, e in spans):
                        found.append(os.path.relpath(path, MODELS))
    return sorted(set(found))


def test_no_unguarded_d365_ref_in_bronze_silver_gold():
    unguarded = _unguarded_d365_refs()
    assert not unguarded, (
        f"stg_d365_fo__ read outside the erp_sources guard in: {unguarded}"
    )


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


STAGING = os.path.join(MODELS, "staging")
ERP_STAGING_DIRS = ("d365_fo", "erpnext")


def _erp_staging_models():
    out = []
    for erp in ERP_STAGING_DIRS:
        d = os.path.join(STAGING, erp)
        for name in sorted(os.listdir(d)):
            if name.startswith(f"stg_{erp}__") and name.endswith(".sql"):
                out.append((erp, name))
    return out


def test_every_erp_has_staging_models():
    erps = {erp for erp, _ in _erp_staging_models()}
    assert erps == set(ERP_STAGING_DIRS), f"staging models found only for {erps}"


@pytest.mark.parametrize("erp,name", _erp_staging_models())
def test_erp_staging_model_enabled_by_erp_sources(erp, name):
    """Each connector's staging model is disabled unless its ERP is listed in
    `erp_sources`, so an unguarded bronze ref fails the parse."""
    with open(os.path.join(STAGING, erp, name)) as f:
        first = f.readline()
    expected = "{{ config(enabled = '%s' in var('erp_sources'" % erp
    assert first.startswith(expected), (
        f"{erp}/{name}: first line must start with {expected!r}, got {first.strip()!r}"
    )


@pytest.mark.parametrize("model,canonical", sorted(CANONICAL_READERS.items()))
def test_canonical_reader_reads_canonical_unguarded(model, canonical):
    sql = _read(model)
    refs = [
        m.start()
        for m in re.finditer(r"ref\(\s*['\"]%s['\"]\s*\)" % re.escape(canonical), sql)
    ]
    assert refs, f"{model} does not read {canonical}"
    spans = _guarded_spans(sql)
    guarded = [p for p in refs if any(s < p < e for s, e in spans)]
    assert not guarded, (
        f"{model}: {canonical} read inside the d365_fo guard (blanks non-D365 sites)"
    )
    assert "empty_relation(" not in sql, (
        f"{model}: no empty branch; {canonical} is already empty without an ERP"
    )
