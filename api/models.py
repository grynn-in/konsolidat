from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime


class BudgetLineInput(BaseModel):
    scenario_id: str = Field(..., min_length=1, max_length=50)
    legal_entity_id: str = Field(..., min_length=1, max_length=10)
    fiscal_year: int = Field(..., ge=2020, le=2099)
    fiscal_period: int = Field(..., ge=1, le=13)
    main_account: str = Field(..., min_length=1, max_length=20)
    dim_cost_center: str = Field(default="", max_length=20)
    dim_department: str = Field(default="", max_length=20)
    amount: float
    submitted_by: str = Field(..., min_length=1, max_length=100)


class BudgetBatchInput(BaseModel):
    lines: list[BudgetLineInput] = Field(..., min_length=1, max_length=5000)


class AssumptionInput(BaseModel):
    scenario_id: str = Field(..., min_length=1)
    assumption_key: str = Field(..., min_length=1)
    assumption_value: str
    legal_entity_id: str = Field(default="")
    fiscal_year: int = Field(default=0, ge=0, le=2099)
    updated_by: str = Field(..., min_length=1)


class ScenarioCreate(BaseModel):
    scenario_id: str = Field(..., min_length=1, max_length=50)
    scenario_name: str = Field(..., min_length=1, max_length=200)
    scenario_type: str = Field(..., pattern="^(budget|forecast|whatif)$")
    base_scenario_id: str = Field(default="")
    created_by: str = Field(..., min_length=1)


class ScenarioResponse(BaseModel):
    scenario_id: str
    scenario_name: str
    scenario_type: str
    is_active: int
    created_at: Optional[datetime] = None


class BudgetResponse(BaseModel):
    scenario_id: str
    legal_entity_id: str
    fiscal_year: int
    fiscal_period: int
    main_account: str
    dim_cost_center: str
    dim_department: str
    amount: float
    submitted_by: str
    submitted_at: Optional[datetime] = None


class StatusResponse(BaseModel):
    status: str
    message: str
    rows_affected: int = 0
