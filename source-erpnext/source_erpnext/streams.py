# Copyright (c) 2024 Open EPM Contributors
# SPDX-License-Identifier: MIT

"""ERPNext Frappe-REST streams for Airbyte CDK.

Every stream reads one ERPNext doctype over ``/api/resource/<DocType>`` with
``limit_start`` / ``limit_page_length`` paging and an ``Authorization: token``
header. Incremental streams add a ``modified`` filter and track the high-water
mark in state. The Budget stream additionally fetches each document's detail to
flatten its ``Budget Account`` child rows (the list endpoint omits child
tables), so it lands one row per budget account line.
"""

import json
import logging
from pathlib import Path
from typing import Any, Iterable, List, Mapping, MutableMapping

import requests
from airbyte_cdk.sources.streams.http import HttpStream
from airbyte_cdk.sources.streams.http.error_handlers import (
    BackoffStrategy,
    ErrorHandler,
    HttpStatusErrorHandler,
)

from .auth import FrappeTokenAuthenticator

logger = logging.getLogger("airbyte")

SCHEMAS_DIR = Path(__file__).parent / "schemas"


class RetryAfterBackoffStrategy(BackoffStrategy):
    """Return Retry-After header seconds when present; None defers to CDK exponential backoff."""

    def backoff_time(
        self,
        response_or_exception: requests.Response | requests.RequestException | None,
        attempt_count: int,
    ) -> float | None:
        if isinstance(response_or_exception, requests.Response):
            retry_after = response_or_exception.headers.get("Retry-After")
            if retry_after:
                try:
                    return float(retry_after)
                except (TypeError, ValueError):
                    pass
        return None


class FrappeStream(HttpStream):
    """Base stream for an ERPNext doctype over the Frappe REST API."""

    primary_key: str | None = "name"
    doctype: str = ""          # Override: ERPNext DocType name, e.g. "GL Entry"
    fields_list: List[str] = []  # Override: doctype fields to request

    page_size: int = 500

    def __init__(self, authenticator: FrappeTokenAuthenticator, page_size: int = 500, **kwargs):
        super().__init__(**kwargs)
        self._auth = authenticator
        self.page_size = page_size

    def get_backoff_strategy(self) -> BackoffStrategy:
        return RetryAfterBackoffStrategy()

    def get_error_handler(self) -> ErrorHandler:
        return HttpStatusErrorHandler(logger=logger, max_retries=5)

    @property
    def url_base(self) -> str:
        return f"{self._auth.host_url}/api/resource/"

    def path(self, **kwargs) -> str:
        return self.doctype

    def request_headers(self, **kwargs) -> Mapping[str, str]:
        headers = dict(self._auth.get_auth_header())
        headers["Accept"] = "application/json"
        return headers

    def request_params(
        self,
        stream_state: Mapping[str, Any] | None = None,
        stream_slice: Mapping[str, Any] | None = None,
        next_page_token: Mapping[str, Any] | None = None,
    ) -> MutableMapping[str, Any]:
        params: MutableMapping[str, Any] = {
            "limit_page_length": str(self.page_size),
            "limit_start": str((next_page_token or {}).get("offset", 0)),
            "order_by": "modified asc",
        }
        if self.fields_list:
            params["fields"] = json.dumps(self.fields_list)
        return params

    def next_page_token(self, response: requests.Response) -> Mapping[str, Any] | None:
        records = response.json().get("data", [])
        if len(records) < self.page_size:
            return None
        offset = 0
        if response.request is not None and response.request.url:
            from urllib.parse import urlparse, parse_qs
            q = parse_qs(urlparse(response.request.url).query)
            vals = q.get("limit_start")
            if vals:
                offset = int(vals[0])
        return {"offset": offset + len(records)}

    def parse_response(self, response: requests.Response, **kwargs) -> Iterable[Mapping[str, Any]]:
        yield from response.json().get("data", [])

    def get_json_schema(self) -> Mapping[str, Any]:
        with open(SCHEMAS_DIR / f"{self.name}.json", "r") as f:
            return json.load(f)


class FrappeIncrementalStream(FrappeStream):
    """Base for streams supporting incremental sync via a `modified` filter."""

    cursor_field = "modified"
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

    def request_params(self, stream_state=None, stream_slice=None, next_page_token=None):
        params = super().request_params(stream_state, stream_slice, next_page_token)
        cursor_value = (stream_state or {}).get(self.cursor_field)
        if cursor_value:
            # Frappe encodes filters as JSON; the operator/field are constants and
            # the value is carried as a JSON string element, so it cannot inject
            # additional filter syntax.
            params["filters"] = json.dumps([[self.cursor_field, ">=", str(cursor_value)]])
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
# Full-refresh master streams
# ---------------------------------------------------------------------------

class Account(FrappeStream):
    name = "account"
    doctype = "Account"
    fields_list = ["name", "account_name", "root_type", "account_type", "company", "disabled", "modified"]


class Company(FrappeStream):
    name = "company"
    doctype = "Company"
    fields_list = ["name", "default_currency", "country", "modified"]


class FiscalYear(FrappeStream):
    name = "fiscal_year"
    doctype = "Fiscal Year"
    fields_list = ["name", "year_start_date", "year_end_date", "modified"]


# ---------------------------------------------------------------------------
# Incremental transactional streams
# ---------------------------------------------------------------------------

class GLEntry(FrappeIncrementalStream):
    name = "gl_entry"
    doctype = "GL Entry"
    fields_list = [
        "name", "company", "posting_date", "fiscal_year", "account",
        "account_currency", "debit", "credit", "against", "voucher_no",
        "voucher_type", "cost_center", "project", "is_cancelled", "remarks",
        "modified",
    ]


class CurrencyExchange(FrappeIncrementalStream):
    name = "currency_exchange"
    doctype = "Currency Exchange"
    fields_list = ["name", "from_currency", "to_currency", "date", "exchange_rate", "modified"]


class Budget(FrappeIncrementalStream):
    """Budget header flattened to one row per `Budget Account` child line.

    The Frappe list endpoint omits child tables, so for each Budget summary we
    fetch the document detail (``/api/resource/Budget/<name>``) and emit one
    record per ``accounts`` child row, denormalizing the parent fields. This
    matches the flattened ``budget`` raw table the dbt adapter expects.
    """

    name = "budget"
    doctype = "Budget"
    fields_list = ["name", "company", "fiscal_year", "cost_center", "project", "modified"]

    def parse_response(self, response: requests.Response, **kwargs) -> Iterable[Mapping[str, Any]]:
        for header in response.json().get("data", []):
            doc_name = header.get("name")
            if not doc_name:
                continue
            detail_url = f"{self._auth.host_url}/api/resource/Budget/{doc_name}"
            resp = requests.get(detail_url, headers=self.request_headers(), timeout=60)
            resp.raise_for_status()
            doc = resp.json().get("data", {})
            base = {
                "name": doc.get("name", doc_name),
                "company": doc.get("company"),
                "fiscal_year": doc.get("fiscal_year"),
                "cost_center": doc.get("cost_center"),
                "project": doc.get("project"),
                "modified": doc.get("modified", header.get("modified")),
            }
            for line in doc.get("accounts", []) or []:
                row = dict(base)
                row["account"] = line.get("account")
                row["budget_amount"] = line.get("budget_amount")
                yield row
