# Copyright (c) 2024 Open EPM Contributors
# SPDX-License-Identifier: MIT

"""Airbyte source connector for ERPNext (Frappe REST API)."""

import logging
from pathlib import Path
from typing import Any, List, Mapping, Tuple

import yaml
from airbyte_cdk.sources import AbstractSource
from airbyte_cdk.models import ConnectorSpecification

from .auth import FrappeTokenAuthenticator
from .streams import (
    Account,
    Budget,
    Company,
    CurrencyExchange,
    FiscalYear,
    GLEntry,
)

logger = logging.getLogger("airbyte")

SPEC_PATH = Path(__file__).parent / "spec.yaml"


class SourceErpnext(AbstractSource):
    """Airbyte source for ERPNext GL-family doctypes over the Frappe REST API."""

    def spec(self, logger: logging.Logger) -> ConnectorSpecification:
        with open(SPEC_PATH, "r") as f:
            spec_dict = yaml.safe_load(f)
        return ConnectorSpecification(**spec_dict)

    def check_connection(
        self, logger: logging.Logger, config: Mapping[str, Any]
    ) -> Tuple[bool, Any]:
        auth = FrappeTokenAuthenticator(config)
        ok, err = auth.check_connection()
        if not ok:
            return False, err
        return True, None

    def streams(self, config: Mapping[str, Any]) -> List:
        auth = FrappeTokenAuthenticator(config)
        page_size = config.get("page_size", 500)
        common = {"authenticator": auth, "page_size": page_size}
        return [
            GLEntry(**common),
            Account(**common),
            Company(**common),
            CurrencyExchange(**common),
            Budget(**common),
            FiscalYear(**common),
        ]
