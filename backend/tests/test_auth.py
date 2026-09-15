"""T03: bearer-token validation per ADR-0011 §3 and role checks per §4.1."""

import base64
import json
import time
from collections.abc import AsyncIterator
from typing import Any

import httpx
import pytest
import respx
from fastapi import Depends, FastAPI
from httpx import ASGITransport, AsyncClient

from app.auth.deps import User, current_user, require_roles
from app.main import create_app

from .conftest import make_settings
from .keys import (
    AUDIENCE,
    JWK_A,
    JWK_B,
    JWKS_URL,
    KID_B,
    PRIVATE_B,
    jwks,
    make_hs256_confusion_token,
    make_token,
    make_unsigned_token,
)


def app_with_probe() -> FastAPI:
    app = create_app(make_settings())

    @app.get("/probe")
    async def probe(user: User = Depends(current_user)) -> dict[str, object]:  # noqa: B008
        return {"sub": user.sub, "roles": sorted(user.roles)}

    @app.get("/admin-probe")
    async def admin_probe(user: User = Depends(require_roles("admin"))) -> dict[str, str]:  # noqa: B008
        return {"sub": user.sub}

    return app


@pytest.fixture
async def jwks_route() -> AsyncIterator[respx.Route]:
    with respx.mock(assert_all_called=False) as router:
        route = router.get(JWKS_URL).mock(return_value=httpx.Response(200, json=jwks(JWK_A)))
        yield route


@pytest.fixture
async def client(jwks_route: respx.Route) -> AsyncIterator[AsyncClient]:
    app = app_with_probe()
    async with (
        app.router.lifespan_context(app),
        AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac,
    ):
        yield ac


def bearer(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


# --- positive ---------------------------------------------------------------------------


async def test_valid_token_is_accepted(client: AsyncClient, jwks_route: respx.Route) -> None:
    resp = await client.get("/probe", headers=bearer(make_token()))
    assert resp.status_code == 200
    assert resp.json() == {"sub": "user-a", "roles": ["user"]}
    assert jwks_route.call_count == 1


async def test_jwks_is_cached_across_requests(client: AsyncClient, jwks_route: respx.Route) -> None:
    for _ in range(3):
        assert (await client.get("/probe", headers=bearer(make_token()))).status_code == 200
    assert jwks_route.call_count == 1


async def test_aud_may_be_a_list_containing_api(client: AsyncClient) -> None:
    token = make_token(aud=["account", AUDIENCE])
    assert (await client.get("/probe", headers=bearer(token))).status_code == 200


async def test_clock_skew_within_leeway_is_tolerated(client: AsyncClient) -> None:
    now = int(time.time())
    token = make_token(nbf=now + 20, iat=now + 20)
    assert (await client.get("/probe", headers=bearer(token))).status_code == 200


# --- negative ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    ("name", "kwargs"),
    [
        ("wrong issuer", {"iss": "https://evil.example/auth/realms/app"}),
        ("wrong audience", {"aud": "other-api"}),
        ("wrong azp", {"azp": "some-other-client"}),
        ("missing azp", {"azp": None}),
        ("expired", {"exp": int(time.time()) - 120}),
        ("not yet valid", {"nbf": int(time.time()) + 120}),
        ("missing sub", {"sub": None}),
        ("empty sub", {"sub": ""}),
        ("wrong typ", {"typ": "Refresh"}),
        ("missing typ", {"typ": None}),
        ("missing exp", {"exp": None}),
    ],
)
async def test_bad_claims_are_rejected(
    client: AsyncClient, name: str, kwargs: dict[str, Any]
) -> None:
    resp = await client.get("/probe", headers=bearer(make_token(**kwargs)))
    assert resp.status_code == 401, name
    assert resp.headers["www-authenticate"].startswith("Bearer")
    assert resp.json() == {"detail": "Not authenticated"}


async def test_alg_none_is_rejected(client: AsyncClient) -> None:
    token = make_unsigned_token()
    assert (await client.get("/probe", headers=bearer(token))).status_code == 401


async def test_hs256_with_public_key_as_secret_is_rejected(client: AsyncClient) -> None:
    # Classic key-confusion attack: HMAC-sign with the RSA public key bytes as the secret.
    token = make_hs256_confusion_token()
    assert (await client.get("/probe", headers=bearer(token))).status_code == 401


async def test_tampered_signature_is_rejected(client: AsyncClient) -> None:
    token = make_token()
    head, payload, sig = token.split(".")
    flipped = ("A" if sig[0] != "A" else "B") + sig[1:]
    resp = await client.get("/probe", headers=bearer(f"{head}.{payload}.{flipped}"))
    assert resp.status_code == 401


async def test_tampered_payload_is_rejected(client: AsyncClient) -> None:
    token = make_token()
    head, payload, sig = token.split(".")
    claims = json.loads(base64.urlsafe_b64decode(payload + "=="))
    claims["realm_access"] = {"roles": ["admin"]}
    forged = base64.urlsafe_b64encode(json.dumps(claims).encode()).rstrip(b"=").decode()
    resp = await client.get("/probe", headers=bearer(f"{head}.{forged}.{sig}"))
    assert resp.status_code == 401


async def test_signed_by_unknown_key_is_rejected(client: AsyncClient) -> None:
    token = make_token(key=PRIVATE_B, kid="kid-a")  # claims kid-a but signed with key B
    assert (await client.get("/probe", headers=bearer(token))).status_code == 401


@pytest.mark.parametrize(
    "headers",
    [
        {},
        {"Authorization": "Basic dXNlcjpwYXNz"},
        {"Authorization": "Bearer"},
        {"Authorization": "Bearer not-a-jwt"},
        {"Authorization": "bearer x.y"},
    ],
)
async def test_missing_or_malformed_credentials(
    client: AsyncClient, headers: dict[str, str]
) -> None:
    resp = await client.get("/probe", headers=headers)
    assert resp.status_code == 401
    assert resp.headers["www-authenticate"].startswith("Bearer")


async def test_token_without_kid_is_rejected(client: AsyncClient) -> None:
    assert (await client.get("/probe", headers=bearer(make_token(kid=None)))).status_code == 401


# --- key rotation / JWKS refresh --------------------------------------------------------


async def test_unknown_kid_triggers_one_refresh_then_401(
    client: AsyncClient, jwks_route: respx.Route
) -> None:
    assert (await client.get("/probe", headers=bearer(make_token()))).status_code == 200
    resp = await client.get("/probe", headers=bearer(make_token(key=PRIVATE_B, kid=KID_B)))
    assert resp.status_code == 401
    assert jwks_route.call_count == 2  # initial load + exactly one refresh


async def test_refresh_is_rate_limited_to_once_per_minute(
    client: AsyncClient, jwks_route: respx.Route
) -> None:
    assert (await client.get("/probe", headers=bearer(make_token()))).status_code == 200
    for _ in range(5):
        token = make_token(key=PRIVATE_B, kid=KID_B)
        assert (await client.get("/probe", headers=bearer(token))).status_code == 401
    assert jwks_route.call_count == 2


async def test_rotated_key_is_picked_up_on_refresh(
    client: AsyncClient, jwks_route: respx.Route
) -> None:
    assert (await client.get("/probe", headers=bearer(make_token()))).status_code == 200
    jwks_route.mock(return_value=httpx.Response(200, json=jwks(JWK_A, JWK_B)))
    token = make_token(key=PRIVATE_B, kid=KID_B)
    assert (await client.get("/probe", headers=bearer(token))).status_code == 200
    assert jwks_route.call_count == 2


async def test_jwks_unavailable_gives_503(jwks_route: respx.Route) -> None:
    jwks_route.mock(return_value=httpx.Response(500))
    app = app_with_probe()
    async with (
        app.router.lifespan_context(app),
        AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac,
    ):
        resp = await ac.get("/probe", headers=bearer(make_token()))
    assert resp.status_code == 503
    assert resp.json() == {"detail": "Authentication service unavailable"}


# --- roles ------------------------------------------------------------------------------


async def test_require_roles_forbids_without_role(client: AsyncClient) -> None:
    resp = await client.get("/admin-probe", headers=bearer(make_token()))
    assert resp.status_code == 403
    assert resp.json() == {"detail": "Forbidden"}


async def test_require_roles_allows_with_role(client: AsyncClient) -> None:
    token = make_token(realm_access={"roles": ["user", "admin"]})
    assert (await client.get("/admin-probe", headers=bearer(token))).status_code == 200


async def test_require_roles_still_requires_valid_token(client: AsyncClient) -> None:
    assert (await client.get("/admin-probe")).status_code == 401
