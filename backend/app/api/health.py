"""Liveness and readiness endpoints (ADR-0008 §5)."""

from fastapi import APIRouter
from pydantic import BaseModel, ConfigDict

router = APIRouter(tags=["health"])


class Health(BaseModel):
    model_config = ConfigDict(extra="forbid")
    status: str


@router.get("/healthz", include_in_schema=False)
async def healthz() -> Health:
    """Liveness: no dependencies are checked."""
    return Health(status="ok")


@router.get("/readyz", include_in_schema=False)
async def readyz() -> Health:
    """Readiness stub; T02 adds the database check."""
    return Health(status="ok")
