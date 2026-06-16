"""Tests for D365 OData streams."""

import json
import warnings
from unittest.mock import patch, MagicMock, PropertyMock

import pytest
import requests

from airbyte_cdk.sources.streams.http.error_handlers import HttpStatusErrorHandler
from source_d365_fno.auth import D365OAuth2Authenticator
from source_d365_fno.streams import (
    D365ODataStream,
    D365IncrementalStream,
    MainAccounts,
    GeneralJournalAccountEntryBiEntities,
    ExchangeRates,
    BudgetRegisterEntries,
    RetryAfterBackoffStrategy,
    odata_filter_literal,
    cursor_is_greater,
)


class TestCursorHelpers:
    def test_numeric_literal_is_bare(self):
        assert odata_filter_literal(800012647) == "800012647"
        assert odata_filter_literal("800012647") == "800012647"

    def test_temporal_literal_is_bare(self):
        assert odata_filter_literal("2024-06-01") == "2024-06-01"

    def test_other_literal_is_quoted_and_escaped(self):
        assert odata_filter_literal("USMF") == "'USMF'"
        assert odata_filter_literal("a' or '1'='1") == "'a'' or ''1''=''1'"

    def test_numeric_high_water_compares_as_int(self):
        # Lexically "9" > "10"; numerically it must not advance the high-water.
        assert cursor_is_greater("10", "9") is True
        assert cursor_is_greater("9", "10") is False

    def test_temporal_high_water_compares_as_string(self):
        assert cursor_is_greater("2024-06-02", "2024-06-01") is True
        assert cursor_is_greater("2024-06-01", "2024-06-02") is False

    def test_first_value_always_greater(self):
        assert cursor_is_greater("1", None) is True


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
        assert stream.cursor_field == "SourceKey"

    def test_gl_cursor_numeric_filter_param(self, mock_auth):
        """GL streams cursor on the numeric SourceKey -> bare OData literal."""
        stream = GeneralJournalAccountEntryBiEntities(
            authenticator=mock_auth,
            environment_url="https://test.operations.dynamics.com",
        )
        params = stream.request_params(stream_state={"SourceKey": 800012647})
        assert params["$filter"] == "SourceKey ge 800012647"

    def test_read_records_tracks_numeric_max_high_water(self, mock_auth):
        """read_records must advance state by NUMERIC max, not lexical.

        Records arrive out of lexical order (9, 100, 10); the persisted cursor
        must be "100", not "9" (lexical "9" > "100" > "10").
        """
        stream = GeneralJournalAccountEntryBiEntities(
            authenticator=mock_auth,
            environment_url="https://test.operations.dynamics.com",
        )
        records = [{"SourceKey": 9}, {"SourceKey": 100}, {"SourceKey": 10}]
        with patch.object(D365ODataStream, "read_records", return_value=iter(records)):
            out = list(stream.read_records(sync_mode="incremental"))
        assert len(out) == 3                 # all records still passed through
        assert stream._cursor_value == "100"  # numeric max, not lexical

    def test_request_params_emits_filter_for_zero_cursor(self, mock_auth):
        """A SourceKey high-water of 0 is valid and must still emit a $filter."""
        stream = GeneralJournalAccountEntryBiEntities(
            authenticator=mock_auth,
            environment_url="https://test.operations.dynamics.com",
        )
        params = stream.request_params(stream_state={"SourceKey": 0})
        assert params["$filter"] == "SourceKey ge 0"

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


class TestBackoffMigration:
    """Verify the CDK backoff/error-handler migration away from deprecated methods."""

    def test_get_backoff_strategy_returns_retry_after_strategy(self, mock_auth):
        stream = MainAccounts(
            authenticator=mock_auth,
            environment_url="https://test.operations.dynamics.com",
        )
        assert isinstance(stream.get_backoff_strategy(), RetryAfterBackoffStrategy)

    def test_get_error_handler_returns_http_status_error_handler(self, mock_auth):
        stream = MainAccounts(
            authenticator=mock_auth,
            environment_url="https://test.operations.dynamics.com",
        )
        assert isinstance(stream.get_error_handler(), HttpStatusErrorHandler)

    def test_backoff_strategy_returns_retry_after_seconds(self):
        strategy = RetryAfterBackoffStrategy()
        resp = MagicMock(spec=requests.Response)
        resp.headers = {"Retry-After": "45"}
        assert strategy.backoff_time(resp, attempt_count=1) == 45.0

    def test_backoff_strategy_returns_none_when_no_header(self):
        strategy = RetryAfterBackoffStrategy()
        resp = MagicMock(spec=requests.Response)
        resp.headers = {}
        assert strategy.backoff_time(resp, attempt_count=1) is None

    def test_backoff_strategy_returns_none_for_non_response(self):
        strategy = RetryAfterBackoffStrategy()
        assert strategy.backoff_time(None, attempt_count=1) is None
        exc = requests.exceptions.ConnectionError("timeout")
        assert strategy.backoff_time(exc, attempt_count=2) is None

    def test_backoff_strategy_returns_none_for_http_date_retry_after(self):
        # RFC-7231 allows an HTTP-date Retry-After; we don't parse it (D365 sends
        # integer seconds) -> falls back to CDK exponential backoff, never crashes.
        strategy = RetryAfterBackoffStrategy()
        resp = MagicMock(spec=requests.Response)
        resp.headers = {"Retry-After": "Wed, 21 Oct 2026 07:28:00 GMT"}
        assert strategy.backoff_time(resp, attempt_count=1) is None

    def test_no_cdk_adapter_deprecation_warnings_on_instantiation(self, mock_auth):
        """Stream instantiation must not trigger CDK backoff/error-handler adapter warnings."""
        with warnings.catch_warnings(record=True) as recorded:
            warnings.simplefilter("always")
            MainAccounts(
                authenticator=mock_auth,
                environment_url="https://test.operations.dynamics.com",
            )
        cdk_adapter_warns = [
            str(w.message) for w in recorded
            if issubclass(w.category, DeprecationWarning)
            and (
                "get_backoff_strategy" in str(w.message)
                or "get_error_handler" in str(w.message)
            )
        ]
        assert cdk_adapter_warns == [], f"Unexpected CDK adapter deprecation warnings: {cdk_adapter_warns}"

    def test_stream_has_no_should_retry_method(self, mock_auth):
        stream = MainAccounts(
            authenticator=mock_auth,
            environment_url="https://test.operations.dynamics.com",
        )
        assert "should_retry" not in type(stream).__dict__

    def test_stream_has_no_backoff_time_method(self, mock_auth):
        stream = MainAccounts(
            authenticator=mock_auth,
            environment_url="https://test.operations.dynamics.com",
        )
        assert "backoff_time" not in type(stream).__dict__
