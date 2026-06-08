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


def test_readme_no_cube():
    """README must not reference Cube.js as active component."""
    with open(os.path.join(PROJECT_ROOT, "README.md")) as f:
        content = f.read()
    assert "Cube.js" not in content
    assert "CubeJS" not in content


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
