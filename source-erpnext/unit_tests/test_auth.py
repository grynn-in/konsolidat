"""Tests for the Frappe token authenticator."""

from unittest.mock import MagicMock, patch

import requests

from source_erpnext.auth import FrappeTokenAuthenticator, auth_error_message


class TestFrappeTokenAuthenticator:
    def test_auth_header(self, config):
        auth = FrappeTokenAuthenticator(config)
        assert auth.get_auth_header() == {
            "Authorization": "token test-api-key:test-api-secret"
        }

    def test_host_url_strips_trailing_slash(self):
        auth = FrappeTokenAuthenticator(
            {"host_url": "https://erp.test.com/", "api_key": "k", "api_secret": "s"}
        )
        assert auth.host_url == "https://erp.test.com"

    def test_check_connection_success(self, config):
        resp = MagicMock()
        resp.raise_for_status.return_value = None
        with patch("source_erpnext.auth.requests.get", return_value=resp):
            ok, err = FrappeTokenAuthenticator(config).check_connection()
        assert ok is True
        assert err is None

    def test_check_connection_http_error(self, config):
        err_resp = MagicMock(status_code=401, text="no")
        http_err = requests.exceptions.HTTPError(response=err_resp)
        resp = MagicMock()
        resp.raise_for_status.side_effect = http_err
        with patch("source_erpnext.auth.requests.get", return_value=resp):
            ok, msg = FrappeTokenAuthenticator(config).check_connection()
        assert ok is False
        assert "HTTP 401" in msg
        # Never leak the raw server body
        assert "no" not in msg.replace("Authentication", "")


class TestAuthErrorMessage:
    def test_http_error_includes_status_only(self):
        err_resp = MagicMock(status_code=403, text="secret-body")
        err = requests.exceptions.HTTPError(response=err_resp)
        msg = auth_error_message(err)
        assert "HTTP 403" in msg
        assert "secret-body" not in msg

    def test_generic_error(self):
        msg = auth_error_message(requests.exceptions.ConnectionError())
        assert "Connection error" in msg
