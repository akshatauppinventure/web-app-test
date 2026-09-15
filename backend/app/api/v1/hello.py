"""GET /v1/hello — records the visit and greets the caller."""

from collections.abc import AsyncGenerator
from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Request, status
from pydantic import BaseModel, ConfigDict
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.deps import User, require_roles
from app.db import Database
from app.services.visits import record_visit

router = APIRouter(tags=["hello"])


class HelloResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    message: str
    visit_count: int
    last_visit: datetime | None


async def user_session(
    request: Request, user: Annotated[User, Depends(require_roles("user"))]
) -> AsyncGenerator[AsyncSession]:
    """A transaction scoped (RLS + service layer) to the authenticated subject."""
    db: Database | None = getattr(request.app.state, "db", None)
    if db is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail="Database unavailable"
        )
    async with db.user_session(user.sub) as session:
        yield session


@router.get("/hello")
async def hello(
    user: Annotated[User, Depends(require_roles("user"))],
    session: Annotated[AsyncSession, Depends(user_session)],
) -> HelloResponse:
    result = await record_visit(session, sub=user.sub, display_name=user.name)
    if result.previous_visit is None:
        message = f"Hello, {result.display_name} — this is your first visit"
    else:
        stamp = result.previous_visit.isoformat().replace("+00:00", "Z")
        message = f"Hello, {result.display_name} — last visit {stamp}"
    return HelloResponse(
        message=message, visit_count=result.visit_count, last_visit=result.previous_visit
    )
