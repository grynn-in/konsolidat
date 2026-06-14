"""Tests for SourceErpnext."""

from unittest.mock import patch, MagicMock

from source_erpnext.source import SourceErpnext


class TestSourceErpnext:
    def test_spec(self):
        source = SourceErpnext()
        spec = source.spec(MagicMock())
        assert spec.connectionSpecification is not None
        required = spec.connectionSpecification["required"]
        assert "host_url" in required
        assert "api_key" in required
        assert "api_secret" in required

    @patch("source_erpnext.source.FrappeTokenAuthenticator")
    def test_check_connection_success(self, mock_auth_cls, config):
        mock_auth = MagicMock()
        mock_auth.check_connection.return_value = (True, None)
        mock_auth_cls.return_value = mock_auth

        source = SourceErpnext()
        ok, err = source.check_connection(MagicMock(), config)

        assert ok is True
        assert err is None

    @patch("source_erpnext.source.FrappeTokenAuthenticator")
    def test_check_connection_failure(self, mock_auth_cls, config):
        mock_auth = MagicMock()
        mock_auth.check_connection.return_value = (False, "Auth failed")
        mock_auth_cls.return_value = mock_auth

        source = SourceErpnext()
        ok, err = source.check_connection(MagicMock(), config)

        assert ok is False
        assert err == "Auth failed"

    @patch("source_erpnext.source.FrappeTokenAuthenticator")
    def test_streams_count(self, mock_auth_cls, config):
        mock_auth_cls.return_value = MagicMock()
        source = SourceErpnext()
        assert len(source.streams(config)) == 6

    @patch("source_erpnext.source.FrappeTokenAuthenticator")
    def test_stream_names(self, mock_auth_cls, config):
        mock_auth_cls.return_value = MagicMock()
        source = SourceErpnext()
        names = {s.name for s in source.streams(config)}
        assert names == {
            "gl_entry",
            "account",
            "company",
            "currency_exchange",
            "budget",
            "fiscal_year",
        }
