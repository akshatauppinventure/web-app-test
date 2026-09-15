"""GET /v1/me — identity as seen by the API."""

from typing import Annotated

from fastapi import APIRouter, Depends
from pydantic import BaseModel, ConfigDict

from app.auth.deps import User, require_roles

router = APIRouter(tags=["me"])


class Me(BaseModel):
    model_config = ConfigDict(extra="forbid")

    sub: str
    name: str
    email: str | None
    roles: list[str]


@router.get("/me")
async def me(user: Annotated[User, Depends(require_roles("user"))]) -> Me:
    return Me(sub=user.sub, name=user.name, email=user.email, roles=sorted(user.roles))
