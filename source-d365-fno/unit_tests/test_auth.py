"""Tests for D365 OAuth2 authenticator."""

from unittest.mock import patch, MagicMock

from source_d365_fno.auth import D365OAuth2Authenticator


class TestD365OAuth2Authenticator:
    def test_token_url_format(self, config):
        auth = D365OAuth2Authenticator(config)
        assert auth.token_url == "https://login.microsoftonline.com/test-tenant-id/oauth2/v2.0/token"

    def test_scope_format(self, config):
        auth = D365OAuth2Authenticator(config)
        assert auth._scope == "https://test.operations.dynamics.com/.default"

    def test_scope_strips_trailing_slash(self):
        config = {
            "tenant_id": "t",
            "client_id": "c",
            "client_secret": "s",
            "environment_url": "https://example.com/",
        }
        auth = D365OAuth2Authenticator(config)
        assert auth._scope == "https://example.com/.default"

    @patch("source_d365_fno.auth.requests.post")
    def test_get_token_success(self, mock_post, config, mock_token_response):
        mock_resp = MagicMock()
        mock_resp.json.return_value = mock_token_response
        mock_resp.raise_for_status = MagicMock()
        mock_post.return_value = mock_resp

        auth = D365OAuth2Authenticator(config)
        token = auth.get_token()

        assert token == "mock-access-token-12345"
        mock_post.assert_called_once()
        call_data = mock_post.call_args[1]["data"]
        assert call_data["grant_type"] == "client_credentials"
        assert call_data["client_id"] == "test-client-id"
        assert call_data["scope"] == "https://test.operations.dynamics.com/.default"

    @patch("source_d365_fno.auth.requests.post")
    def test_token_caching(self, mock_post, config, mock_token_response):
        mock_resp = MagicMock()
        mock_resp.json.return_value = mock_token_response
        mock_resp.raise_for_status = MagicMock()
        mock_post.return_value = mock_resp

        auth = D365OAuth2Authenticator(config)
        token1 = auth.get_token()
        token2 = auth.get_token()

        assert token1 == token2
        assert mock_post.call_count == 1  # Only one HTTP call

    @patch("source_d365_fno.auth.requests.post")
    def test_get_auth_header(self, mock_post, config, mock_token_response):
        mock_resp = MagicMock()
        mock_resp.json.return_value = mock_token_response
        mock_resp.raise_for_status = MagicMock()
        mock_post.return_value = mock_resp

        auth = D365OAuth2Authenticator(config)
        header = auth.get_auth_header()

        assert header == {"Authorization": "Bearer mock-access-token-12345"}

    @patch("source_d365_fno.auth.requests.post")
    def test_check_connection_success(self, mock_post, config, mock_token_response):
        mock_resp = MagicMock()
        mock_resp.json.return_value = mock_token_response
        mock_resp.raise_for_status = MagicMock()
        mock_post.return_value = mock_resp

        auth = D365OAuth2Authenticator(config)
        ok, err = auth.check_connection()

        assert ok is True
        assert err is None

    @patch("source_d365_fno.auth.requests.post")
    def test_check_connection_failure(self, mock_post, config):
        import requests
        mock_resp = MagicMock()
        mock_resp.status_code = 401
        mock_resp.text = "Invalid client"
        mock_resp.raise_for_status.side_effect = requests.exceptions.HTTPError(response=mock_resp)
        mock_post.return_value = mock_resp

        auth = D365OAuth2Authenticator(config)
        ok, err = auth.check_connection()

        assert ok is False
        assert "Authentication failed" in err
