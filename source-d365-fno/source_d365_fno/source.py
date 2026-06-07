# Copyright (c) 2024 Open EPM Contributors
# SPDX-License-Identifier: MIT

"""Airbyte source connector for D365 Finance & Operations."""

import logging
from pathlib import Path
from typing import Any, List, Mapping, Tuple

import yaml
from airbyte_cdk.sources import AbstractSource
from airbyte_cdk.models import ConnectorSpecification

from .auth import D365OAuth2Authenticator
from .streams import (
    BudgetRegisterEntries,
    ConsolidateAccountGroups,
    DimensionAttributes,
    ExchangeRates,
    ExchangeRateTypes,
    FiscalCalendarYears,
    FinancialDimensionValues,
    GeneralJournalAccountEntryBiEntities,
    GeneralJournalEntryBiEntities,
    LegalEntities,
    Ledgers,
    MainAccountCategories,
    MainAccounts,
    TrialBalanceFiscalYearSnapshots,
)

logger = logging.getLogger("airbyte")

SPEC_PATH = Path(__file__).parent / "spec.yaml"


class SourceD365Fno(AbstractSource):
    """Airbyte source for D365 Finance & Operations OData entities."""

    def spec(self, logger: logging.Logger) -> ConnectorSpecification:
        with open(SPEC_PATH, "r") as f:
            spec_dict = yaml.safe_load(f)
        return ConnectorSpecification(**spec_dict)

    def check_connection(
        self, logger: logging.Logger, config: Mapping[str, Any]
    ) -> Tuple[bool, Any]:
        auth = D365OAuth2Authenticator(config)
        ok, err = auth.check_connection()
        if not ok:
            return False, err
        return True, None

    def streams(self, config: Mapping[str, Any]) -> List:
        auth = D365OAuth2Authenticator(config)
        env_url = config["environment_url"]
        page_size = config.get("page_size", 5000)

        common = {
            "authenticator": auth,
            "environment_url": env_url,
            "page_size": page_size,
        }

        return [
            GeneralJournalAccountEntryBiEntities(**common),
            GeneralJournalEntryBiEntities(**common),
            MainAccounts(**common),
            MainAccountCategories(**common),
            LegalEntities(**common),
            Ledgers(**common),
            FiscalCalendarYears(**common),
            DimensionAttributes(**common),
            FinancialDimensionValues(**common),
            ExchangeRates(**common),
            ExchangeRateTypes(**common),
            BudgetRegisterEntries(**common),
            ConsolidateAccountGroups(**common),
            TrialBalanceFiscalYearSnapshots(**common),
        ]
