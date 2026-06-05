#!/usr/bin/env python3
"""Generate Cube YAML schemas from dbt_project.yml vars (dimensions + measures).

Usage:
    python scripts/generate_cube_schemas.py [--dbt-project dbt_project/dbt_project.yml]

Reads the `vars.dimensions` and `vars.base_measures` config from dbt_project.yml
and generates 4 cube schema files + 4 cube view files under cube/.
"""

import argparse
import sys
from pathlib import Path

import yaml


def load_vars(dbt_project_path: str) -> dict:
    with open(dbt_project_path) as f:
        project = yaml.safe_load(f)
    return project.get("vars", {})


def build_trial_balance_cube(dimensions: list, measures: list) -> dict:
    dims = [
        {"name": "data_area_id", "sql": "data_area_id", "type": "string", "title": "Legal Entity"},
        {"name": "fiscal_year", "sql": "fiscal_year", "type": "number", "title": "Fiscal Year"},
        {"name": "fiscal_period", "sql": "fiscal_period", "type": "number", "title": "Period"},
        {"name": "main_account", "sql": "main_account", "type": "string", "title": "Account"},
        {"name": "account_name", "sql": "account_name", "type": "string", "title": "Account Name"},
        {"name": "account_type_name", "sql": "account_type_name", "type": "string", "title": "Account Type"},
        {"name": "is_balance_sheet", "sql": "is_balance_sheet", "type": "boolean", "title": "Is Balance Sheet"},
        {"name": "is_pnl", "sql": "is_pnl", "type": "boolean", "title": "Is P&L"},
    ]
    for d in dimensions:
        dims.append({
            "name": d["name"],
            "sql": d["name"],
            "type": d.get("cube_type", "string"),
            "title": d.get("label", d["name"]),
        })

    cube_measures = []
    for m in measures:
        cube_measures.append({
            "name": m["name"],
            "sql": m["name"],
            "type": m.get("cube_type", "sum"),
            "title": m.get("label", m["name"]),
        })

    return {
        "cubes": [{
            "name": "trial_balance",
            "sql_table": "epm_gold.gold_trial_balance",
            "data_source": "default",
            "dimensions": dims,
            "measures": cube_measures,
        }]
    }


def build_allocation_results_cube() -> dict:
    return {
        "cubes": [{
            "name": "allocation_results",
            "sql_table": "epm_gold.gold_allocation_results",
            "data_source": "default",
            "dimensions": [
                {"name": "allocation_rule_id", "sql": "allocation_rule_id", "type": "string", "title": "Rule"},
                {"name": "data_area_id", "sql": "data_area_id", "type": "string", "title": "Legal Entity"},
                {"name": "fiscal_year", "sql": "fiscal_year", "type": "number", "title": "Fiscal Year"},
                {"name": "fiscal_period", "sql": "fiscal_period", "type": "number", "title": "Period"},
                {"name": "source_account", "sql": "source_account", "type": "string", "title": "Source Account"},
                {"name": "target_cost_center", "sql": "target_cost_center", "type": "string", "title": "Target Cost Center"},
                {"name": "driver_type", "sql": "driver_type", "type": "string", "title": "Driver"},
            ],
            "measures": [
                {"name": "pool_amount", "sql": "pool_amount", "type": "sum", "title": "Pool Amount"},
                {"name": "allocated_amount", "sql": "allocated_amount", "type": "sum", "title": "Allocated Amount"},
                {"name": "driver_weight", "sql": "driver_weight", "type": "avg", "title": "Weight"},
            ],
        }]
    }


def build_consolidated_trial_balance_cube() -> dict:
    return {
        "cubes": [{
            "name": "consolidated_trial_balance",
            "sql_table": "epm_gold.gold_consolidated_trial_balance",
            "data_source": "default",
            "dimensions": [
                {"name": "consolidation_group", "sql": "consolidation_group", "type": "string", "title": "Group"},
                {"name": "data_area_id", "sql": "data_area_id", "type": "string", "title": "Legal Entity"},
                {"name": "fiscal_year", "sql": "fiscal_year", "type": "number", "title": "Fiscal Year"},
                {"name": "fiscal_period", "sql": "fiscal_period", "type": "number", "title": "Period"},
                {"name": "main_account", "sql": "main_account", "type": "string", "title": "Account"},
                {"name": "account_name", "sql": "account_name", "type": "string", "title": "Account Name"},
                {"name": "reporting_currency", "sql": "reporting_currency", "type": "string", "title": "Reporting Currency"},
            ],
            "measures": [
                {"name": "local_amount", "sql": "local_amount", "type": "sum", "title": "Local Amount"},
                {"name": "group_amount", "sql": "group_amount", "type": "sum", "title": "Group Amount"},
                {"name": "ownership_pct", "sql": "ownership_pct", "type": "avg", "title": "Ownership %"},
            ],
        }]
    }


def build_scenario_trial_balance_cube(dimensions: list) -> dict:
    budget_dims = [d for d in dimensions if d.get("in_budget", False)]

    dims = [
        {"name": "scenario_id", "sql": "scenario_id", "type": "string", "title": "Scenario"},
        {"name": "data_area_id", "sql": "data_area_id", "type": "string", "title": "Legal Entity"},
        {"name": "fiscal_year", "sql": "fiscal_year", "type": "number", "title": "Fiscal Year"},
        {"name": "fiscal_period", "sql": "fiscal_period", "type": "number", "title": "Period"},
        {"name": "main_account", "sql": "main_account", "type": "string", "title": "Account"},
        {"name": "account_name", "sql": "account_name", "type": "string", "title": "Account Name"},
    ]
    for d in budget_dims:
        dims.append({
            "name": d["name"],
            "sql": d["name"],
            "type": d.get("cube_type", "string"),
            "title": d.get("label", d["name"]),
        })

    return {
        "cubes": [{
            "name": "scenario_trial_balance",
            "sql_table": "epm_gold.gold_scenario_trial_balance",
            "data_source": "default",
            "dimensions": dims,
            "measures": [
                {"name": "amount", "sql": "amount", "type": "sum", "title": "Amount"},
                {
                    "name": "actual_amount",
                    "sql": "CASE WHEN scenario_id = 'ACTUAL' THEN amount ELSE 0 END",
                    "type": "sum",
                    "title": "Actual",
                },
                {
                    "name": "budget_amount",
                    "sql": "CASE WHEN scenario_id = 'BUDGET' THEN amount ELSE 0 END",
                    "type": "sum",
                    "title": "Budget",
                },
                {
                    "name": "variance",
                    "sql": "CASE WHEN scenario_id = 'ACTUAL' THEN amount ELSE 0 END - CASE WHEN scenario_id = 'BUDGET' THEN amount ELSE 0 END",
                    "type": "sum",
                    "title": "Variance",
                },
            ],
        }]
    }


def build_balance_sheet_view(dimensions: list) -> dict:
    includes = [
        "data_area_id", "fiscal_year", "fiscal_period",
        "main_account", "account_name", "account_type_name",
    ]
    for d in dimensions:
        includes.append(d["name"])
    includes.extend(["period_debit", "period_credit", "period_net_amount"])

    return {
        "views": [{
            "name": "v_balance_sheet",
            "description": "Balance sheet view for Excel PivotTables",
            "cubes": [{
                "join_path": "trial_balance",
                "includes": includes,
            }],
            "meta": {"sql_filter": "trial_balance.is_balance_sheet = true"},
        }]
    }


def build_pnl_report_view(dimensions: list, measures: list) -> dict:
    includes = [
        "data_area_id", "fiscal_year", "fiscal_period",
        "main_account", "account_name",
    ]
    for d in dimensions:
        includes.append(d["name"])
    for m in measures:
        includes.append(m["name"])

    return {
        "views": [{
            "name": "v_pnl_report",
            "description": "P&L report view for Excel PivotTables",
            "cubes": [{
                "join_path": "trial_balance",
                "includes": includes,
            }],
            "meta": {"sql_filter": "trial_balance.is_pnl = true"},
        }]
    }


def build_budget_vs_actual_view(dimensions: list) -> dict:
    budget_dims = [d for d in dimensions if d.get("in_budget", False)]
    includes = [
        "data_area_id", "fiscal_year", "fiscal_period",
        "main_account", "account_name",
    ]
    for d in budget_dims:
        includes.append(d["name"])
    includes.extend(["actual_amount", "budget_amount", "variance"])

    return {
        "views": [{
            "name": "v_budget_vs_actual",
            "description": "Budget vs Actual comparison for Excel",
            "cubes": [{
                "join_path": "scenario_trial_balance",
                "includes": includes,
            }],
        }]
    }


def build_consolidated_report_view() -> dict:
    return {
        "views": [{
            "name": "v_consolidated_report",
            "description": "Consolidated group report for Excel",
            "cubes": [{
                "join_path": "consolidated_trial_balance",
                "includes": [
                    "consolidation_group", "data_area_id",
                    "fiscal_year", "fiscal_period",
                    "main_account", "account_name",
                    "reporting_currency",
                    "local_amount", "group_amount", "ownership_pct",
                ],
            }],
        }]
    }


def write_yaml(data: dict, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w") as f:
        yaml.dump(data, f, default_flow_style=False, sort_keys=False, allow_unicode=True)
    print(f"  wrote {path}")


def main():
    parser = argparse.ArgumentParser(description="Generate Cube schemas from dbt_project.yml vars")
    parser.add_argument(
        "--dbt-project",
        default="dbt_project/dbt_project.yml",
        help="Path to dbt_project.yml (default: dbt_project/dbt_project.yml)",
    )
    parser.add_argument(
        "--output-dir",
        default="cube",
        help="Output directory for Cube schemas (default: cube)",
    )
    args = parser.parse_args()

    vars_config = load_vars(args.dbt_project)
    dimensions = vars_config.get("dimensions", [])
    measures = vars_config.get("base_measures", [])

    if not dimensions:
        print("WARNING: No dimensions found in vars config", file=sys.stderr)
    if not measures:
        print("WARNING: No base_measures found in vars config", file=sys.stderr)

    output = Path(args.output_dir)

    print("Generating Cube schemas...")

    # Schema files (cubes)
    write_yaml(build_trial_balance_cube(dimensions, measures), output / "schema" / "trial_balance.yml")
    write_yaml(build_allocation_results_cube(), output / "schema" / "allocation_results.yml")
    write_yaml(build_consolidated_trial_balance_cube(), output / "schema" / "consolidated_trial_balance.yml")
    write_yaml(build_scenario_trial_balance_cube(dimensions), output / "schema" / "scenario_trial_balance.yml")

    # View files
    write_yaml(build_balance_sheet_view(dimensions), output / "views" / "v_balance_sheet.yml")
    write_yaml(build_pnl_report_view(dimensions, measures), output / "views" / "v_pnl_report.yml")
    write_yaml(build_budget_vs_actual_view(dimensions), output / "views" / "v_budget_vs_actual.yml")
    write_yaml(build_consolidated_report_view(), output / "views" / "v_consolidated_report.yml")

    print("Done! Generated 4 schema files + 4 view files.")


if __name__ == "__main__":
    main()
