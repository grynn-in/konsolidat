"""Tests for SourceD365Fno."""

from unittest.mock import patch, MagicMock

from source_d365_fno.source import SourceD365Fno


class TestSourceD365Fno:
    def test_spec(self):
        source = SourceD365Fno()
        spec = source.spec(MagicMock())
        assert spec.connectionSpecification is not None
        required = spec.connectionSpecification["required"]
        assert "tenant_id" in required
        assert "client_id" in required
        assert "client_secret" in required
        assert "environment_url" in required

    @patch("source_d365_fno.source.D365OAuth2Authenticator")
    def test_check_connection_success(self, mock_auth_cls, config):
        mock_auth = MagicMock()
        mock_auth.check_connection.return_value = (True, None)
        mock_auth_cls.return_value = mock_auth

        source = SourceD365Fno()
        ok, err = source.check_connection(MagicMock(), config)

        assert ok is True
        assert err is None

    @patch("source_d365_fno.source.D365OAuth2Authenticator")
    def test_check_connection_failure(self, mock_auth_cls, config):
        mock_auth = MagicMock()
        mock_auth.check_connection.return_value = (False, "Auth failed")
        mock_auth_cls.return_value = mock_auth

        source = SourceD365Fno()
        ok, err = source.check_connection(MagicMock(), config)

        assert ok is False
        assert err == "Auth failed"

    @patch("source_d365_fno.source.D365OAuth2Authenticator")
    def test_streams_count(self, mock_auth_cls, config):
        mock_auth = MagicMock()
        mock_auth_cls.return_value = mock_auth

        source = SourceD365Fno()
        streams = source.streams(config)

        assert len(streams) == 14

    @patch("source_d365_fno.source.D365OAuth2Authenticator")
    def test_stream_names(self, mock_auth_cls, config):
        mock_auth = MagicMock()
        mock_auth_cls.return_value = mock_auth

        source = SourceD365Fno()
        streams = source.streams(config)
        names = {s.name for s in streams}

        expected = {
            "general_journal_account_entry_bi_entities",
            "general_journal_entry_bi_entities",
            "main_accounts",
            "main_account_categories",
            "legal_entities",
            "ledgers",
            "fiscal_calendar_years",
            "dimension_attributes",
            "financial_dimension_values",
            "exchange_rates",
            "exchange_rate_types",
            "budget_register_entries",
            "consolidate_account_groups",
            "trial_balance_fiscal_year_snapshots",
        }
        assert names == expected
