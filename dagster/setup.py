from setuptools import find_packages, setup

setup(
    name="open_epm_dagster",
    packages=find_packages(),
    install_requires=[
        "dagster",
        "dagster-dbt",
        "dagster-airbyte",
        "dbt-core",
        "dbt-clickhouse",
    ],
)
