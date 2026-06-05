from fastapi import FastAPI, HTTPException
from contextlib import asynccontextmanager

from models import (
    BudgetLineInput,
    BudgetBatchInput,
    AssumptionInput,
    ScenarioCreate,
    ScenarioResponse,
    BudgetResponse,
    StatusResponse,
)
from db import get_client


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Verify ClickHouse connection on startup
    client = get_client()
    client.command("SELECT 1")
    client.close()
    yield


app = FastAPI(
    title="Open EPM Write-Back API",
    description="Budget and forecast input API for Open EPM",
    version="1.0.0",
    lifespan=lifespan,
)


@app.post("/api/v1/budget", response_model=StatusResponse)
def post_budget(batch: BudgetBatchInput):
    """Insert budget lines into staging table."""
    client = get_client()
    try:
        rows = [
            [
                line.scenario_id,
                line.legal_entity_id,
                line.fiscal_year,
                line.fiscal_period,
                line.main_account,
                line.dim_cost_center,
                line.dim_department,
                line.amount,
                line.submitted_by,
            ]
            for line in batch.lines
        ]
        client.insert(
            "epm_staging.budget_input",
            rows,
            column_names=[
                "scenario_id",
                "legal_entity_id",
                "fiscal_year",
                "fiscal_period",
                "main_account",
                "dim_cost_center",
                "dim_department",
                "amount",
                "submitted_by",
            ],
        )
        return StatusResponse(
            status="ok",
            message=f"Inserted {len(rows)} budget lines",
            rows_affected=len(rows),
        )
    finally:
        client.close()


@app.post("/api/v1/assumptions", response_model=StatusResponse)
def post_assumptions(assumptions: list[AssumptionInput]):
    """Insert planning assumptions into staging table."""
    client = get_client()
    try:
        rows = [
            [
                a.scenario_id,
                a.assumption_key,
                a.assumption_value,
                a.legal_entity_id,
                a.fiscal_year,
                a.updated_by,
            ]
            for a in assumptions
        ]
        client.insert(
            "epm_staging.planning_assumptions",
            rows,
            column_names=[
                "scenario_id",
                "assumption_key",
                "assumption_value",
                "legal_entity_id",
                "fiscal_year",
                "updated_by",
            ],
        )
        return StatusResponse(
            status="ok",
            message=f"Inserted {len(rows)} assumptions",
            rows_affected=len(rows),
        )
    finally:
        client.close()


@app.get("/api/v1/scenarios", response_model=list[ScenarioResponse])
def list_scenarios():
    """List all available scenarios."""
    client = get_client()
    try:
        result = client.query(
            "SELECT scenario_id, scenario_name, scenario_type, is_active, created_at "
            "FROM epm_staging.scenario_definitions FINAL "
            "ORDER BY scenario_id"
        )
        return [
            ScenarioResponse(
                scenario_id=row[0],
                scenario_name=row[1],
                scenario_type=row[2],
                is_active=row[3],
                created_at=row[4],
            )
            for row in result.result_rows
        ]
    finally:
        client.close()


@app.post("/api/v1/scenarios", response_model=StatusResponse)
def create_scenario(scenario: ScenarioCreate):
    """Create a new scenario."""
    client = get_client()
    try:
        # Check if scenario already exists
        existing = client.query(
            "SELECT count() FROM epm_staging.scenario_definitions FINAL "
            "WHERE scenario_id = {id:String}",
            parameters={"id": scenario.scenario_id},
        )
        if existing.result_rows[0][0] > 0:
            raise HTTPException(
                status_code=409,
                detail=f"Scenario '{scenario.scenario_id}' already exists",
            )

        client.insert(
            "epm_staging.scenario_definitions",
            [
                [
                    scenario.scenario_id,
                    scenario.scenario_name,
                    scenario.scenario_type,
                    scenario.base_scenario_id,
                    1,  # is_active
                    scenario.created_by,
                ]
            ],
            column_names=[
                "scenario_id",
                "scenario_name",
                "scenario_type",
                "base_scenario_id",
                "is_active",
                "created_by",
            ],
        )
        return StatusResponse(
            status="ok",
            message=f"Scenario '{scenario.scenario_id}' created",
            rows_affected=1,
        )
    finally:
        client.close()


@app.get("/api/v1/budget/{scenario_id}", response_model=list[BudgetResponse])
def get_budget(scenario_id: str, limit: int = 1000):
    """Read back budget lines for validation."""
    client = get_client()
    try:
        result = client.query(
            "SELECT scenario_id, legal_entity_id, fiscal_year, fiscal_period, "
            "main_account, dim_cost_center, dim_department, amount, "
            "submitted_by, submitted_at "
            "FROM epm_staging.budget_input "
            "WHERE scenario_id = {id:String} "
            "ORDER BY fiscal_year, fiscal_period, main_account "
            "LIMIT {lim:UInt32}",
            parameters={"id": scenario_id, "lim": limit},
        )
        return [
            BudgetResponse(
                scenario_id=row[0],
                legal_entity_id=row[1],
                fiscal_year=row[2],
                fiscal_period=row[3],
                main_account=row[4],
                dim_cost_center=row[5],
                dim_department=row[6],
                amount=float(row[7]),
                submitted_by=row[8],
                submitted_at=row[9],
            )
            for row in result.result_rows
        ]
    finally:
        client.close()


@app.get("/health")
def health():
    """Health check endpoint."""
    client = get_client()
    try:
        client.command("SELECT 1")
        return {"status": "healthy"}
    except Exception as e:
        raise HTTPException(status_code=503, detail=str(e))
    finally:
        client.close()
