"""Liveness and readiness endpoints (ADR-0008 §5)."""

from fastapi import APIRouter, Request, Response
from pydantic import BaseModel, ConfigDict

from app.db import Database

router = APIRouter(tags=["health"])


class Health(BaseModel):
    model_config = ConfigDict(extra="forbid")
    status: str


@router.get("/healthz", include_in_schema=False)
async def healthz() -> Health:
    """Liveness: no dependencies are checked."""
    return Health(status="ok")


@router.get("/readyz", include_in_schema=False)
async def readyz(request: Request, response: Response) -> Health:
    """Readiness: the database must answer. 503 when unconfigured or unreachable."""
    db: Database | None = getattr(request.app.state, "db", None)
    if db is not None and await db.ping():
        return Health(status="ok")
    response.status_code = 503
    return Health(status="unavailable")
