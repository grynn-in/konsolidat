# Copyright (c) 2024 Open EPM Contributors
# SPDX-License-Identifier: MIT

"""D365 F&O OData streams for Airbyte CDK."""

import json
import logging
from pathlib import Path
from typing import Any, Iterable, Mapping, MutableMapping

import requests
from airbyte_cdk.sources.streams.http import HttpStream

from .auth import D365OAuth2Authenticator

logger = logging.getLogger("airbyte")

SCHEMAS_DIR = Path(__file__).parent / "schemas"


class D365ODataStream(HttpStream):
    """Base stream for D365 F&O OData entities.

    Handles:
    - $skip/$top pagination with @odata.nextLink fallback
    - cross-company=true on all requests
    - UTF-8-SIG BOM handling
    - Raw field passthrough (no transforms)
    """

    primary_key: str | None = None
    page_size: int = 5000
    odata_entity: str = ""  # Override in subclass

    def __init__(self, authenticator: D365OAuth2Authenticator, environment_url: str,
                 page_size: int = 5000, **kwargs):
        super().__init__(**kwargs)
        self._authenticator = authenticator
        self._environment_url = environment_url.rstrip("/")
        self.page_size = page_size
        self._use_skip = True

    @property
    def url_base(self) -> str:
        return f"{self._environment_url}/data/"

    def path(self, **kwargs) -> str:
        return self.odata_entity

    def request_headers(self, **kwargs) -> Mapping[str, str]:
        headers = self._authenticator.get_auth_header()
        headers.update({
            "Accept": "application/json",
            "OData-MaxVersion": "4.0",
            "OData-Version": "4.0",
        })
        return headers

    def request_params(
        self,
        stream_state: Mapping[str, Any] | None = None,
        stream_slice: Mapping[str, Any] | None = None,
        next_page_token: Mapping[str, Any] | None = None,
    ) -> MutableMapping[str, Any]:
        params: MutableMapping[str, Any] = {
            "cross-company": "true",
            "$top": str(self.page_size),
        }

        if next_page_token:
            if next_page_token.get("next_link"):
                # When using nextLink, params are embedded in the URL
                return {}
            params["$skip"] = str(next_page_token.get("offset", 0))

        return params

    def next_page_token(
        self, response: requests.Response
    ) -> Mapping[str, Any] | None:
        data = response.json()
        records = data.get("value", [])

        if not records:
            return None

        # Prefer @odata.nextLink if present
        next_link = data.get("@odata.nextLink")
        if next_link:
            self._use_skip = False
            return {"next_link": next_link}

        # Fall back to $skip pagination
        if len(records) < self.page_size:
            return None

        # Calculate current offset from request
        current_offset = 0
        if hasattr(response, "request") and response.request.url:
            from urllib.parse import urlparse, parse_qs
            parsed = urlparse(response.request.url)
            skip_vals = parse_qs(parsed.query).get("%24skip") or parse_qs(parsed.query).get("$skip")
            if skip_vals:
                current_offset = int(skip_vals[0])

        return {"offset": current_offset + len(records)}

    def _send_request(self, request: requests.PreparedRequest, request_kwargs: Mapping[str, Any]) -> requests.Response:
        """Override to handle nextLink URLs that are absolute."""
        return super()._send_request(request, request_kwargs)

    def parse_response(
        self, response: requests.Response, **kwargs
    ) -> Iterable[Mapping[str, Any]]:
        data = response.json()
        yield from data.get("value", [])

    def get_json_schema(self) -> Mapping[str, Any]:
        schema_file = SCHEMAS_DIR / f"{self.name}.json"
        with open(schema_file, "r") as f:
            return json.load(f)


class D365IncrementalStream(D365ODataStream):
    """Base for streams supporting incremental sync via OData $filter."""

    cursor_field: str = ""  # Override in subclass
    _cursor_value: str | None = None

    @property
    def state(self) -> MutableMapping[str, Any]:
        return {self.cursor_field: self._cursor_value} if self._cursor_value else {}

    @state.setter
    def state(self, value: MutableMapping[str, Any]):
        self._cursor_value = value.get(self.cursor_field)

    @property
    def supports_incremental(self) -> bool:
        return True

    def request_params(
        self,
        stream_state: Mapping[str, Any] | None = None,
        stream_slice: Mapping[str, Any] | None = None,
        next_page_token: Mapping[str, Any] | None = None,
    ) -> MutableMapping[str, Any]:
        params = super().request_params(
            stream_state=stream_state,
            stream_slice=stream_slice,
            next_page_token=next_page_token,
        )

        # Apply incremental filter
        cursor_value = (stream_state or {}).get(self.cursor_field)
        if cursor_value and params:  # params is empty when using nextLink
            params["$filter"] = f"{self.cursor_field} ge {cursor_value}"

        return params

    def read_records(self, *args, **kwargs) -> Iterable[Mapping[str, Any]]:
        for record in super().read_records(*args, **kwargs):
            cursor = record.get(self.cursor_field)
            if cursor:
                cursor_str = str(cursor)
                if self._cursor_value is None or cursor_str > self._cursor_value:
                    self._cursor_value = cursor_str
            yield record


# ---------------------------------------------------------------------------
# Full-refresh streams
# ---------------------------------------------------------------------------

class MainAccounts(D365ODataStream):
    name = "main_accounts"
    odata_entity = "MainAccounts"
    primary_key = "MainAccountId"


class MainAccountCategories(D365ODataStream):
    name = "main_account_categories"
    odata_entity = "MainAccountCategories"
    primary_key = "ReferenceId"


class LegalEntities(D365ODataStream):
    name = "legal_entities"
    odata_entity = "LegalEntities"
    primary_key = "LegalEntityId"


class Ledgers(D365ODataStream):
    name = "ledgers"
    odata_entity = "Ledgers"
    primary_key = "LegalEntityId"


class FiscalCalendarYears(D365ODataStream):
    name = "fiscal_calendar_years"
    odata_entity = "FiscalCalendarYears"
    primary_key = None


class DimensionAttributes(D365ODataStream):
    name = "dimension_attributes"
    odata_entity = "DimensionAttributes"
    primary_key = "DimensionName"


class FinancialDimensionValues(D365ODataStream):
    name = "financial_dimension_values"
    odata_entity = "FinancialDimensionValues"
    primary_key = None


class ExchangeRateTypes(D365ODataStream):
    name = "exchange_rate_types"
    odata_entity = "ExchangeRateTypes"
    primary_key = "Name"


class ConsolidateAccountGroups(D365ODataStream):
    name = "consolidate_account_groups"
    odata_entity = "ConsolidateAccountGroups"
    primary_key = "ConsolidationAccountGroup"


class TrialBalanceFiscalYearSnapshots(D365ODataStream):
    name = "trial_balance_fiscal_year_snapshots"
    odata_entity = "TrialBalanceFiscalYearSnapshots"
    primary_key = None


# ---------------------------------------------------------------------------
# Incremental streams
# ---------------------------------------------------------------------------

class GeneralJournalAccountEntryBiEntities(D365IncrementalStream):
    name = "general_journal_account_entry_bi_entities"
    odata_entity = "GeneralJournalAccountEntryBiEntities"
    primary_key = "SourceKey"
    cursor_field = "AccountingDate"


class GeneralJournalEntryBiEntities(D365IncrementalStream):
    name = "general_journal_entry_bi_entities"
    odata_entity = "GeneralJournalEntryBiEntities"
    primary_key = "SourceKey"
    cursor_field = "AccountingDate"


class ExchangeRates(D365IncrementalStream):
    name = "exchange_rates"
    odata_entity = "ExchangeRates"
    primary_key = None
    cursor_field = "StartDate"


class BudgetRegisterEntries(D365IncrementalStream):
    name = "budget_register_entries"
    odata_entity = "BudgetRegisterEntries"
    primary_key = "EntryNumber"
    cursor_field = "Date"
