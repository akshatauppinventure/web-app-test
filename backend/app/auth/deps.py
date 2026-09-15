"""FastAPI dependencies: ``current_user`` and ``require_roles`` (ADR-0011 §3-4)."""

from collections.abc import Callable, Coroutine
from typing import Annotated, Any, cast

import jwt
import structlog
from fastapi import Depends, HTTPException, Request, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, ConfigDict

from app.auth.jwks import JWKSClient, JWKSUnavailableError
from app.config import Settings

log = structlog.get_logger("app.auth")
_bearer = HTTPBearer(auto_error=False)


class User(BaseModel):
    model_config = ConfigDict(frozen=True, extra="forbid")

    sub: str
    name: str
    email: str | None
    roles: frozenset[str]


def _unauthenticated() -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Not authenticated",
        headers={"WWW-Authenticate": 'Bearer realm="api"'},
    )


def _jwks_client(request: Request) -> JWKSClient:
    return request.app.state.jwks


def _settings(request: Request) -> Settings:
    return request.app.state.settings


def _display_name(claims: dict[str, Any], sub: str) -> str:
    for key in ("name", "preferred_username"):
        value = claims.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()[:255]
    return sub


async def current_user(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer)],
    jwks: Annotated[JWKSClient, Depends(_jwks_client)],
    settings: Annotated[Settings, Depends(_settings)],
) -> User:
    if credentials is None or credentials.scheme.lower() != "bearer" or not credentials.credentials:
        raise _unauthenticated()
    token = credentials.credentials

    try:
        header = jwt.get_unverified_header(token)
    except jwt.PyJWTError:
        raise _unauthenticated() from None
    alg = header.get("alg")
    kid = header.get("kid")
    if alg not in settings.oidc_algorithms or not isinstance(kid, str) or not kid:
        log.info("token_rejected", reason="header", alg=alg)
        raise _unauthenticated()

    try:
        key = await jwks.get_key(kid)
    except JWKSUnavailableError:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Authentication service unavailable",
        ) from None
    if key is None:
        log.info("token_rejected", reason="unknown_kid")
        raise _unauthenticated()

    try:
        claims: dict[str, Any] = jwt.decode(
            token,
            key,
            algorithms=list(settings.oidc_algorithms),
            audience=settings.oidc_audience,
            issuer=settings.oidc_issuer,
            leeway=settings.oidc_leeway_seconds,
            options={"require": ["exp", "iat", "sub", "iss", "aud"]},
        )
    except jwt.PyJWTError as exc:
        log.info("token_rejected", reason=type(exc).__name__)
        raise _unauthenticated() from None

    sub = claims.get("sub")
    if not isinstance(sub, str) or not sub:
        raise _unauthenticated()
    if claims.get("typ") != "Bearer":
        log.info("token_rejected", reason="typ")
        raise _unauthenticated()
    if claims.get("azp") != settings.oidc_authorized_party:
        log.info("token_rejected", reason="azp")
        raise _unauthenticated()

    realm_access: object = claims.get("realm_access")
    raw_roles: object = (
        cast(dict[str, object], realm_access).get("roles")
        if isinstance(realm_access, dict)
        else None
    )
    role_list = cast(list[object], raw_roles) if isinstance(raw_roles, list) else []
    roles = frozenset(r for r in role_list if isinstance(r, str))
    email = claims.get("email")
    return User(
        sub=sub,
        name=_display_name(claims, sub),
        email=email if isinstance(email, str) else None,
        roles=roles,
    )


CurrentUser = Annotated[User, Depends(current_user)]


def require_roles(*required: str) -> Callable[..., Coroutine[Any, Any, User]]:
    """Dependency factory: the caller must hold every listed realm role."""
    needed = frozenset(required)

    async def _check(user: CurrentUser) -> User:
        if not needed.issubset(user.roles):
            log.info("forbidden", missing=sorted(needed - user.roles))
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Forbidden")
        return user

    return _check
