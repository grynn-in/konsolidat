from dagster import ScheduleDefinition, DefaultScheduleStatus

from open_epm_dagster.assets.dbt_assets import open_epm_dbt_assets

# Daily schedule: run full dbt build at 6 AM
daily_refresh_schedule = ScheduleDefinition(
    name="daily_epm_refresh",
    target=open_epm_dbt_assets,
    cron_schedule="0 6 * * *",
    default_status=DefaultScheduleStatus.STOPPED,
)
