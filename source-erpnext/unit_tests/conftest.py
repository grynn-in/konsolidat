"""Shared fixtures for source-erpnext unit tests."""

import pytest


@pytest.fixture
def config():
    return {
        "host_url": "https://erp.test.com",
        "api_key": "test-api-key",
        "api_secret": "test-api-secret",
        "page_size": 500,
    }


@pytest.fixture
def mock_gl_entry_response():
    return {
        "data": [
            {
                "name": "ACC-GLE-2024-00001",
                "company": "Test Co",
                "posting_date": "2024-01-15",
                "fiscal_year": "2024-2025",
                "account": "1110 - Cash - TC",
                "account_currency": "USD",
                "debit": 1500.0,
                "credit": 0.0,
                "cost_center": "Main - TC",
                "project": "PRJ-001",
                "is_cancelled": 0,
                "voucher_no": "JV-00001",
                "voucher_type": "Journal Entry",
                "modified": "2024-01-15 10:00:00",
            },
        ],
    }


@pytest.fixture
def mock_budget_list_response():
    return {"data": [{"name": "BUDGET-001", "modified": "2024-01-01 09:00:00"}]}


@pytest.fixture
def mock_budget_detail_response():
    return {
        "data": {
            "name": "BUDGET-001",
            "company": "Test Co",
            "fiscal_year": "2024-2025",
            "cost_center": "Main - TC",
            "project": None,
            "modified": "2024-01-01 09:00:00",
            "accounts": [
                {"account": "5110 - Salaries - TC", "budget_amount": 50000.0},
                {"account": "5120 - Rent - TC", "budget_amount": 12000.0},
            ],
        }
    }
