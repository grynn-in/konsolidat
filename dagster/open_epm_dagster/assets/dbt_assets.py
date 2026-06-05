import os
from pathlib import Path

from dagster import AssetKey, AssetExecutionContext
from dagster_dbt import DbtCliResource, dbt_assets, DagsterDbtTranslator, DbtProject


# Path to dbt project (relative to dagster app root)
DBT_PROJECT_DIR = Path(__file__).parent.parent.parent.parent / "dbt_project"
DBT_PROFILES_DIR = DBT_PROJECT_DIR


class OpenEpmDbtTranslator(DagsterDbtTranslator):
    """Custom translator that maps dbt sources to Airbyte asset keys."""

    def get_asset_key(self, dbt_resource_props: dict) -> AssetKey:
        resource_type = dbt_resource_props.get("resource_type", "")
        if resource_type == "source":
            # Map Airbyte-synced sources to the Airbyte asset namespace
            source_name = dbt_resource_props.get("source_name", "")
            table_name = dbt_resource_props.get("name", "")
            if source_name == "airbyte_raw":
                return AssetKey(["airbyte", table_name])
        # Default: use dbt model name
        return super().get_asset_key(dbt_resource_props)


dbt_project = DbtProject(
    project_dir=DBT_PROJECT_DIR,
    profiles_dir=DBT_PROFILES_DIR,
)


@dbt_assets(
    manifest=dbt_project.manifest_path,
    dagster_dbt_translator=OpenEpmDbtTranslator(),
)
def open_epm_dbt_assets(context: AssetExecutionContext, dbt: DbtCliResource):
    """Run dbt models as Dagster assets."""
    yield from dbt.cli(["build"], context=context).stream()
