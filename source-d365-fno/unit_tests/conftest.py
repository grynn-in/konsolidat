"""Shared fixtures for source-d365-fno unit tests."""

import pytest


@pytest.fixture
def config():
    return {
        "tenant_id": "test-tenant-id",
        "client_id": "test-client-id",
        "client_secret": "test-client-secret",
        "environment_url": "https://test.operations.dynamics.com",
        "page_size": 5000,
    }


@pytest.fixture
def mock_token_response():
    return {
        "access_token": "mock-access-token-12345",
        "token_type": "Bearer",
        "expires_in": 3600,
    }


@pytest.fixture
def mock_odata_response_page1():
    """First page of OData response with nextLink."""
    return {
        "value": [
            {"MainAccountId": "110100", "Name": "Cash", "MainAccountType": "BalanceSheet"},
            {"MainAccountId": "110200", "Name": "Petty Cash", "MainAccountType": "BalanceSheet"},
        ],
        "@odata.nextLink": "https://test.operations.dynamics.com/data/MainAccounts?$skip=2&$top=2",
    }


@pytest.fixture
def mock_odata_response_page2():
    """Last page of OData response (no nextLink)."""
    return {
        "value": [
            {"MainAccountId": "401000", "Name": "Revenue", "MainAccountType": "Revenue"},
        ],
    }


@pytest.fixture
def mock_gl_entry_bi_response():
    """Mock GL entry BI entity response."""
    return {
        "value": [
            {
                "SourceKey": 1001,
                "SubledgerVoucherDataAreaId": "usmf",
                "AccountingDate": "2024-01-15T00:00:00Z",
                "JournalNumber": "GJ-000001",
                "JournalCategory": "General",
                "DocumentNumber": "DOC001",
                "DocumentDate": "2024-01-15T00:00:00Z",
                "SubledgerVoucher": "Voucher 001",
                "PostingLayer": "Current",
                "FiscalCalendarPeriod": 5637144576,
                "FiscalCalendarYear": 5637144577,
            },
        ],
    }


@pytest.fixture
def mock_gl_account_entry_bi_response():
    """Mock GL account entry BI entity response."""
    return {
        "value": [
            {
                "SourceKey": 2001,
                "GeneralJournalEntry": 1001,
                "LedgerAccount": "140200-001-022",
                "LedgerDimensionValuesJson": '[{"MAINACCOUNT":"140200","COSTCENTER":"001","DEPARTMENT":"022"}]',
                "AccountingCurrencyAmount": 1500.00,
                "ReportingCurrencyAmount": 0.0,
                "TransactionCurrencyAmount": 1500.00,
                "TransactionCurrencyCode": "USD",
                "PostingType": "LedgerJournal",
                "Text": "Office supplies",
                "IsCredit": "No",
                "AccountingDate": "2024-01-15T00:00:00Z",
            },
        ],
    }


@pytest.fixture
def mock_exchange_rate_response():
    """Mock exchange rates with ConversionFactor."""
    return {
        "value": [
            {
                "FromCurrency": "EUR",
                "ToCurrency": "USD",
                "StartDate": "2024-01-01T00:00:00Z",
                "EndDate": "2024-12-31T00:00:00Z",
                "Rate": 1.08,
                "ConversionFactor": "One",
                "RateTypeName": "Spot",
            },
            {
                "FromCurrency": "GBP",
                "ToCurrency": "USD",
                "StartDate": "2024-01-01T00:00:00Z",
                "EndDate": "2024-12-31T00:00:00Z",
                "Rate": 127.50,
                "ConversionFactor": "Hundred",
                "RateTypeName": "Spot",
            },
        ],
    }


@pytest.fixture
def mock_budget_response():
    """Mock budget register entries (combined header+line)."""
    return {
        "value": [
            {
                "EntryNumber": "BUD-001",
                "dataAreaId": "usmf",
                "BudgetModelId": "Budget2024",
                "BudgetCode": "Original",
                "ReasonComment": "Annual budget",
                "Status": "Completed",
                "Date": "2024-01-01T00:00:00Z",
                "DimensionDisplayValue": "601200-002-022--",
                "AccountingCurrencyAmount": 50000.00,
                "TransactionCurrencyAmount": 50000.00,
                "CurrencyCode": "USD",
                "BusinessUnit": "002",
                "Department": "022",
                "IncludeInCashFlowForecast": "No",
            },
            {
                "EntryNumber": "BUD-001",
                "dataAreaId": "usmf",
                "BudgetModelId": "Budget2024",
                "BudgetCode": "Original",
                "ReasonComment": "Annual budget",
                "Status": "Completed",
                "Date": "2024-02-01T00:00:00Z",
                "DimensionDisplayValue": "601300-002-022--",
                "AccountingCurrencyAmount": 30000.00,
                "TransactionCurrencyAmount": 30000.00,
                "CurrencyCode": "USD",
                "BusinessUnit": "002",
                "Department": "022",
                "IncludeInCashFlowForecast": "No",
            },
        ],
    }
