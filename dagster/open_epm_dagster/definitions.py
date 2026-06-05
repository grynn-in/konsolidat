import os
from pathlib import Path

from dagster import Definitions
from dagster_dbt import DbtCliResource

from open_epm_dagster.assets.dbt_assets import open_epm_dbt_assets, DBT_PROJECT_DIR
from open_epm_dagster.schedules.daily_refresh import daily_refresh_schedule

# Conditionally load Airbyte assets if configured
try:
    from open_epm_dagster.assets.airbyte_assets import airbyte_assets

    all_assets = [open_epm_dbt_assets, *airbyte_assets]
except Exception:
    # Airbyte not configured - run without it
    all_assets = [open_epm_dbt_assets]


defs = Definitions(
    assets=all_assets,
    schedules=[daily_refresh_schedule],
    resources={
        "dbt": DbtCliResource(
            project_dir=str(DBT_PROJECT_DIR),
            profiles_dir=str(DBT_PROJECT_DIR),
        ),
    },
)
