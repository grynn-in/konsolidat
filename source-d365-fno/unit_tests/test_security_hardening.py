"""Tests for connector hardening fixes.

Covers:
  - #26 OData $filter injection safety (odata_filter_literal)
  - #30 throttle/transient retry with backoff
  - #31 configurable cross-company
  - #27 auth error messages do not leak server response bodies

No monkeypatching: streams and the authenticator are constructed for real
(instantiation triggers no network), and error rendering is a pure function.
"""
import requests

from source_d365_fno.auth import D365OAuth2Authenticator, auth_error_message
from source_d365_fno.streams import (
    ExchangeRates,
    MainAccounts,
    odata_filter_literal,
)

ENV = "https://test.operations.dynamics.com"


def _authenticator(config):
    # __init__ only stores config — no token is fetched until a request runs.
    return D365OAuth2Authenticator(config)


def _response(status, headers=None):
    """A minimal real Response object (no mocking framework)."""
    r = requests.Response()
    r.status_code = status
    if headers:
        r.headers.update(headers)
    return r


# ---------------------------------------------------------------------------
# #26 OData filter injection safety
# ---------------------------------------------------------------------------

class TestODataFilterLiteral:
    def test_iso_date_passthrough(self):
        assert odata_filter_literal("2024-06-01") == "2024-06-01"

    def test_iso_datetime_passthrough(self):
        assert odata_filter_literal("2024-01-15T00:00:00Z") == "2024-01-15T00:00:00Z"

    def test_non_temporal_is_quoted(self):
        assert odata_filter_literal("abc") == "'abc'"

    def test_single_quotes_are_doubled(self):
        assert odata_filter_literal("2024' or '1'='1") == "'2024'' or ''1''=''1'"

    def test_injection_does_not_break_out_of_filter(self, config):
        stream = ExchangeRates(authenticator=_authenticator(config), environment_url=ENV)
        malicious = "2024-01-01 or 1 eq 1"
        params = stream.request_params(stream_state={"StartDate": malicious})
        assert params["$filter"] == "StartDate ge '2024-01-01 or 1 eq 1'"

    def test_clean_cursor_still_unquoted(self, config):
        stream = ExchangeRates(authenticator=_authenticator(config), environment_url=ENV)
        params = stream.request_params(stream_state={"StartDate": "2024-06-01"})
        assert params["$filter"] == "StartDate ge 2024-06-01"


# ---------------------------------------------------------------------------
# #31 configurable cross-company
# ---------------------------------------------------------------------------

class TestCrossCompany:
    def test_default_is_cross_company(self, config):
        stream = MainAccounts(authenticator=_authenticator(config), environment_url=ENV)
        assert stream.request_params()["cross-company"] == "true"

    def test_can_be_disabled(self, config):
        stream = MainAccounts(authenticator=_authenticator(config), environment_url=ENV,
                              cross_company=False)
        assert "cross-company" not in stream.request_params()


# ---------------------------------------------------------------------------
# #30 retry / backoff
# ---------------------------------------------------------------------------

class TestRetryBackoff:
    def test_retries_on_429(self, config):
        stream = MainAccounts(authenticator=_authenticator(config), environment_url=ENV)
        assert stream.should_retry(_response(429)) is True

    def test_retries_on_5xx(self, config):
        stream = MainAccounts(authenticator=_authenticator(config), environment_url=ENV)
        assert stream.should_retry(_response(503)) is True

    def test_no_retry_on_200(self, config):
        stream = MainAccounts(authenticator=_authenticator(config), environment_url=ENV)
        assert stream.should_retry(_response(200)) is False

    def test_honours_retry_after(self, config):
        stream = MainAccounts(authenticator=_authenticator(config), environment_url=ENV)
        assert stream.backoff_time(_response(429, {"Retry-After": "7"})) == 7.0

    def test_falls_back_without_retry_after(self, config):
        stream = MainAccounts(authenticator=_authenticator(config), environment_url=ENV)
        assert stream.backoff_time(_response(429)) is None


# ---------------------------------------------------------------------------
# #27 auth error messages do not leak server response bodies
# ---------------------------------------------------------------------------

class TestAuthErrorRedaction:
    def test_http_error_message_is_generic(self):
        resp = _response(401)
        resp._content = b"SECRET_LEAK client_secret=hunter2"
        err = requests.exceptions.HTTPError(response=resp)
        msg = auth_error_message(err)
        assert "SECRET_LEAK" not in msg
        assert "hunter2" not in msg
        assert "401" in msg

    def test_connection_error_message_is_generic(self):
        err = requests.exceptions.ConnectionError("dns boom at 10.0.0.5")
        msg = auth_error_message(err)
        assert "10.0.0.5" not in msg
        assert msg == "Connection error: ConnectionError"
