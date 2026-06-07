"""Tests for D365 OData streams."""

import json
from unittest.mock import patch, MagicMock, PropertyMock

import pytest

from source_d365_fno.auth import D365OAuth2Authenticator
from source_d365_fno.streams import (
    D365ODataStream,
    D365IncrementalStream,
    MainAccounts,
    GeneralJournalAccountEntryBiEntities,
    ExchangeRates,
    BudgetRegisterEntries,
)


@pytest.fixture
def mock_auth(config):
    with patch.object(D365OAuth2Authenticator, "get_token", return_value="mock-token"):
        auth = D365OAuth2Authenticator(config)
        yield auth


class TestD365ODataStream:
    def test_url_base(self, mock_auth):
        stream = MainAccounts(
            authenticator=mock_auth,
            environment_url="https://test.operations.dynamics.com",
        )
        assert stream.url_base == "https://test.operations.dynamics.com/data/"

    def test_path(self, mock_auth):
        stream = MainAccounts(
            authenticator=mock_auth,
            environment_url="https://test.operations.dynamics.com",
        )
        assert stream.path() == "MainAccounts"

    def test_request_headers(self, mock_auth):
        stream = MainAccounts(
            authenticator=mock_auth,
            environment_url="https://test.operations.dynamics.com",
        )
        headers = stream.request_headers()
        assert "Authorization" in headers
        assert headers["Accept"] == "application/json"
        assert headers["OData-Version"] == "4.0"

    def test_request_params_first_page(self, mock_auth):
        stream = MainAccounts(
            authenticator=mock_auth,
            environment_url="https://test.operations.dynamics.com",
            page_size=1000,
        )
        params = stream.request_params()
        assert params["cross-company"] == "true"
        assert params["$top"] == "1000"
        assert "$skip" not in params

    def test_request_params_with_skip(self, mock_auth):
        stream = MainAccounts(
            authenticator=mock_auth,
            environment_url="https://test.operations.dynamics.com",
        )
        params = stream.request_params(next_page_token={"offset": 5000})
        assert params["$skip"] == "5000"

    def test_request_params_with_next_link(self, mock_auth):
        stream = MainAccounts(
            authenticator=mock_auth,
            environment_url="https://test.operations.dynamics.com",
        )
        params = stream.request_params(next_page_token={"next_link": "https://example.com/next"})
        assert params == {}  # nextLink contains all params

    def test_parse_response(self, mock_auth, mock_odata_response_page1):
        stream = MainAccounts(
            authenticator=mock_auth,
            environment_url="https://test.operations.dynamics.com",
        )
        mock_resp = MagicMock()
        mock_resp.json.return_value = mock_odata_response_page1

        records = list(stream.parse_response(mock_resp))
        assert len(records) == 2
        assert records[0]["MainAccountId"] == "110100"
        assert records[1]["MainAccountId"] == "110200"

    def test_next_page_token_with_next_link(self, mock_auth, mock_odata_response_page1):
        stream = MainAccounts(
            authenticator=mock_auth,
            environment_url="https://test.operations.dynamics.com",
        )
        mock_resp = MagicMock()
        mock_resp.json.return_value = mock_odata_response_page1

        token = stream.next_page_token(mock_resp)
        assert token is not None
        assert "next_link" in token

    def test_next_page_token_last_page(self, mock_auth, mock_odata_response_page2):
        stream = MainAccounts(
            authenticator=mock_auth,
            environment_url="https://test.operations.dynamics.com",
            page_size=5000,
        )
        mock_resp = MagicMock()
        mock_resp.json.return_value = mock_odata_response_page2

        token = stream.next_page_token(mock_resp)
        assert token is None

    def test_get_json_schema(self, mock_auth):
        stream = MainAccounts(
            authenticator=mock_auth,
            environment_url="https://test.operations.dynamics.com",
        )
        schema = stream.get_json_schema()
        assert "properties" in schema
        assert "MainAccountId" in schema["properties"]


class TestIncrementalStream:
    def test_supports_incremental(self, mock_auth):
        stream = GeneralJournalAccountEntryBiEntities(
            authenticator=mock_auth,
            environment_url="https://test.operations.dynamics.com",
        )
        assert stream.supports_incremental is True
        assert stream.cursor_field == "AccountingDate"

    def test_incremental_filter_param(self, mock_auth):
        stream = ExchangeRates(
            authenticator=mock_auth,
            environment_url="https://test.operations.dynamics.com",
        )
        state = {"StartDate": "2024-06-01"}
        params = stream.request_params(stream_state=state)
        assert "$filter" in params
        assert params["$filter"] == "StartDate ge 2024-06-01"

    def test_no_filter_without_state(self, mock_auth):
        stream = ExchangeRates(
            authenticator=mock_auth,
            environment_url="https://test.operations.dynamics.com",
        )
        params = stream.request_params(stream_state={})
        assert "$filter" not in params

    def test_state_tracking(self, mock_auth):
        stream = BudgetRegisterEntries(
            authenticator=mock_auth,
            environment_url="https://test.operations.dynamics.com",
        )
        assert stream.state == {}

        stream.state = {"Date": "2024-01-01"}
        assert stream._cursor_value == "2024-01-01"

    def test_field_passthrough(self, mock_auth, mock_odata_response_page1):
        """Verify raw OData fields pass through without transformation."""
        stream = MainAccounts(
            authenticator=mock_auth,
            environment_url="https://test.operations.dynamics.com",
        )
        mock_resp = MagicMock()
        mock_resp.json.return_value = mock_odata_response_page1

        records = list(stream.parse_response(mock_resp))
        # Fields should be exactly as in OData response
        assert records[0]["MainAccountId"] == "110100"
        assert records[0]["Name"] == "Cash"
        assert records[0]["MainAccountType"] == "BalanceSheet"
