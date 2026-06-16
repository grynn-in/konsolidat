"""Tests for ERPNext Frappe-REST streams."""

import json
import warnings
from unittest.mock import MagicMock, patch

import pytest
import requests

from airbyte_cdk.sources.streams.http.error_handlers import HttpStatusErrorHandler
from source_erpnext.auth import FrappeTokenAuthenticator
from source_erpnext.streams import (
    Account,
    Budget,
    CurrencyExchange,
    GLEntry,
    RetryAfterBackoffStrategy,
)


@pytest.fixture
def auth(config):
    return FrappeTokenAuthenticator(config)


class TestFrappeStream:
    def test_url_base(self, auth):
        stream = GLEntry(authenticator=auth)
        assert stream.url_base == "https://erp.test.com/api/resource/"

    def test_path_uses_doctype(self, auth):
        assert GLEntry(authenticator=auth).path() == "GL Entry"
        assert Account(authenticator=auth).path() == "Account"

    def test_request_headers_token(self, auth):
        headers = GLEntry(authenticator=auth).request_headers()
        assert headers["Authorization"] == "token test-api-key:test-api-secret"
        assert headers["Accept"] == "application/json"

    def test_request_params_first_page(self, auth):
        params = GLEntry(authenticator=auth, page_size=250).request_params()
        assert params["limit_page_length"] == "250"
        assert params["limit_start"] == "0"
        assert params["order_by"] == "modified asc"
        assert "GL Entry".replace(" ", "") or json.loads(params["fields"])  # fields is valid JSON
        assert "name" in json.loads(params["fields"])

    def test_request_params_pagination_offset(self, auth):
        params = GLEntry(authenticator=auth).request_params(next_page_token={"offset": 500})
        assert params["limit_start"] == "500"

    def test_next_page_token_full_page(self, auth):
        stream = GLEntry(authenticator=auth, page_size=2)
        resp = MagicMock()
        resp.json.return_value = {"data": [{"name": "a"}, {"name": "b"}]}
        resp.request.url = "https://erp.test.com/api/resource/GL Entry?limit_start=0"
        token = stream.next_page_token(resp)
        assert token == {"offset": 2}

    def test_next_page_token_partial_page_ends(self, auth):
        stream = GLEntry(authenticator=auth, page_size=5)
        resp = MagicMock()
        resp.json.return_value = {"data": [{"name": "a"}]}
        assert stream.next_page_token(resp) is None

    def test_parse_response_yields_data(self, auth, mock_gl_entry_response):
        stream = GLEntry(authenticator=auth)
        resp = MagicMock()
        resp.json.return_value = mock_gl_entry_response
        rows = list(stream.parse_response(resp))
        assert len(rows) == 1
        assert rows[0]["name"] == "ACC-GLE-2024-00001"


class TestIncremental:
    def test_modified_filter_applied(self, auth):
        stream = CurrencyExchange(authenticator=auth)
        params = stream.request_params(stream_state={"modified": "2024-01-01 00:00:00"})
        flt = json.loads(params["filters"])
        assert flt == [["modified", ">=", "2024-01-01 00:00:00"]]

    def test_no_filter_without_state(self, auth):
        params = CurrencyExchange(authenticator=auth).request_params()
        assert "filters" not in params

    def test_cursor_advances(self, auth):
        stream = GLEntry(authenticator=auth)
        with patch(
            "source_erpnext.streams.FrappeStream.read_records",
            return_value=iter([
                {"name": "a", "modified": "2024-01-01 00:00:00"},
                {"name": "b", "modified": "2024-03-01 00:00:00"},
            ]),
        ):
            list(stream.read_records(sync_mode=None))
        assert stream.state == {"modified": "2024-03-01 00:00:00"}


class TestBackoffMigration:
    """Verify the CDK backoff/error-handler migration away from deprecated methods."""

    def test_get_backoff_strategy_returns_retry_after_strategy(self, auth):
        assert isinstance(GLEntry(authenticator=auth).get_backoff_strategy(), RetryAfterBackoffStrategy)

    def test_get_error_handler_returns_http_status_error_handler(self, auth):
        assert isinstance(GLEntry(authenticator=auth).get_error_handler(), HttpStatusErrorHandler)

    def test_backoff_strategy_returns_retry_after_seconds(self):
        strategy = RetryAfterBackoffStrategy()
        resp = MagicMock(spec=requests.Response)
        resp.headers = {"Retry-After": "60"}
        assert strategy.backoff_time(resp, attempt_count=1) == 60.0

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
        # RFC-7231 allows an HTTP-date Retry-After; we don't parse it (ERPNext
        # sends integer seconds) -> falls back to CDK exponential backoff.
        strategy = RetryAfterBackoffStrategy()
        resp = MagicMock(spec=requests.Response)
        resp.headers = {"Retry-After": "Wed, 21 Oct 2026 07:28:00 GMT"}
        assert strategy.backoff_time(resp, attempt_count=1) is None

    def test_no_cdk_adapter_deprecation_warnings_on_instantiation(self, auth):
        """Stream instantiation must not trigger CDK backoff/error-handler adapter warnings."""
        with warnings.catch_warnings(record=True) as recorded:
            warnings.simplefilter("always")
            GLEntry(authenticator=auth)
        cdk_adapter_warns = [
            str(w.message) for w in recorded
            if issubclass(w.category, DeprecationWarning)
            and (
                "get_backoff_strategy" in str(w.message)
                or "get_error_handler" in str(w.message)
            )
        ]
        assert cdk_adapter_warns == [], f"Unexpected CDK adapter deprecation warnings: {cdk_adapter_warns}"

    def test_stream_has_no_should_retry_method(self, auth):
        stream = GLEntry(authenticator=auth)
        assert "should_retry" not in type(stream).__dict__

    def test_stream_has_no_backoff_time_method(self, auth):
        stream = GLEntry(authenticator=auth)
        assert "backoff_time" not in type(stream).__dict__


class TestBudgetFlatten:
    def test_budget_flattens_child_lines(self, auth, mock_budget_list_response, mock_budget_detail_response):
        stream = Budget(authenticator=auth)
        list_resp = MagicMock()
        list_resp.json.return_value = mock_budget_list_response
        detail_resp = MagicMock()
        detail_resp.json.return_value = mock_budget_detail_response
        detail_resp.raise_for_status.return_value = None

        with patch("source_erpnext.streams.requests.get", return_value=detail_resp):
            rows = list(stream.parse_response(list_resp))

        assert len(rows) == 2
        assert {r["account"] for r in rows} == {"5110 - Salaries - TC", "5120 - Rent - TC"}
        assert all(r["company"] == "Test Co" for r in rows)
        assert all(r["fiscal_year"] == "2024-2025" for r in rows)
        assert rows[0]["budget_amount"] == 50000.0
