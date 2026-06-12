"""TDD tests for updated documentation."""
import os

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def test_readme_mentions_frappe():
    """README must mention Frappe as the control layer."""
    with open(os.path.join(PROJECT_ROOT, "README.md")) as f:
        content = f.read()
    assert "Frappe" in content or "frappe" in content


def test_readme_no_streamlit():
    """README must not reference Streamlit as active component."""
    with open(os.path.join(PROJECT_ROOT, "README.md")) as f:
        content = f.read()
    assert "Streamlit" not in content


def test_readme_documents_cube():
    """Cube.js is a core component — README must mention it.

    Cube is the semantic / SQL-API layer that scales concurrent reads to the
    target 50–500 users (Excel ODBC and BI tools query through it). The Frappe
    direct-query path remains the source of truth for the =EPM() formulas and
    write-back. See docs/reference/semantic-layer.md.
    """
    with open(os.path.join(PROJECT_ROOT, "README.md")) as f:
        content = f.read()
    assert "Cube" in content


def test_readme_no_dagster():
    """README must not reference Dagster as active component."""
    with open(os.path.join(PROJECT_ROOT, "README.md")) as f:
        content = f.read()
    assert "Dagster" not in content


def test_readme_mentions_clickhouse():
    """README must mention ClickHouse."""
    with open(os.path.join(PROJECT_ROOT, "README.md")) as f:
        content = f.read()
    assert "ClickHouse" in content


def test_readme_mentions_dbt():
    """README must mention dbt."""
    with open(os.path.join(PROJECT_ROOT, "README.md")) as f:
        content = f.read()
    assert "dbt" in content


def test_readme_mentions_konsol():
    """README must mention the konsol app."""
    with open(os.path.join(PROJECT_ROOT, "README.md")) as f:
        content = f.read()
    assert "konsol" in content or "Konsol" in content
