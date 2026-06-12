"""Contract-parity tests for the two =EPM() clients.

The Office.js add-in (taskpane.js) and the VBA module (OpenEPM.bas) implement
the same wire protocol independently. These tests pin the shared invariants
documented in docs/reference/epm-formula-protocol.md so the two cannot silently
drift apart again (see issue #28).
"""
import os

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

JS_PATH = os.path.join(PROJECT_ROOT, "excel-addin", "src", "taskpane.js")
BAS_PATH = os.path.join(PROJECT_ROOT, "excel", "OpenEPM.bas")
DOC_PATH = os.path.join(PROJECT_ROOT, "docs", "reference", "epm-formula-protocol.md")


def _read(path):
    with open(path) as f:
        return f.read()


JS = _read(JS_PATH)
BAS = _read(BAS_PATH)
DOC = _read(DOC_PATH)


# --- both clients target the same endpoint ---------------------------------

def test_both_clients_call_epm_batch():
    assert "konsol.api.epm_batch" in JS
    assert "konsol.api.epm_batch" in BAS


# --- request shape: a bare JSON array, not an object wrapper ----------------

def test_js_posts_bare_array():
    assert "JSON.stringify(queries)" in JS
    assert "JSON.stringify({ queries" not in JS  # the old, wrong wrapper


def test_bas_posts_bare_array():
    # VBA builds the batch body as a JSON array literal.
    assert 'json = "["' in BAS


# --- canonical request keys (year/period, not fiscal_*) ---------------------

def test_js_uses_canonical_batch_keys():
    # The epm_batch query objects use `year:` (not the `fiscal_year:` doctype
    # key, which is correct only for the budget_save_batch write-back payload).
    assert "year: fiscalYear" in JS
    # Scope the negative check to the epm_batch refresh block.
    batch_block = JS.split("konsol.api.epm_batch")[0].rsplit("queries = []", 1)[-1]
    assert "fiscal_year:" not in batch_block


def test_bas_uses_canonical_batch_keys():
    assert '""year"":' in BAS
    assert '""period"":' in BAS


# --- response shape: read values[] out of the wrapped message ---------------

def test_js_reads_values_from_message():
    assert "data.message" in JS
    assert ".values" in JS


# --- the protocol doc stays the source of truth -----------------------------

def test_protocol_doc_pins_the_contract():
    assert "konsol.api.epm_batch" in DOC
    assert "bare JSON array" in DOC
    assert "2000" in DOC            # MAX_BATCH_SIZE
    for key in ("entity", "year", "period", "account", "measure", "scenario"):
        assert key in DOC
