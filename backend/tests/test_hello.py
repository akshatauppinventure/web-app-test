"""T03: /v1/me and /v1/hello (ADR-0008 §5, ADR-0011 §4.2)."""

from collections.abc import AsyncIterator

import httpx
import pytest
import respx
from httpx import ASGITransport, AsyncClient
from sqlalchemy import text

from app.db import Database
from app.main import create_app

from .conftest import make_settings
from .db_fixtures import pg_url, requires_postgres
from .keys import JWK_A, JWKS_URL, jwks, make_token


def bearer(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
async def client() -> AsyncIterator[AsyncClient]:
    with respx.mock(assert_all_called=False) as router:
        router.get(JWKS_URL).mock(return_value=httpx.Response(200, json=jwks(JWK_A)))
        app = create_app(make_settings(database_url=pg_url("app_rw")))
        async with (
            app.router.lifespan_context(app),
            AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac,
        ):
            yield ac


@pytest.fixture
async def nodb_client() -> AsyncIterator[AsyncClient]:
    with respx.mock(assert_all_called=False) as router:
        router.get(JWKS_URL).mock(return_value=httpx.Response(200, json=jwks(JWK_A)))
        app = create_app(make_settings())
        async with (
            app.router.lifespan_context(app),
            AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac,
        ):
            yield ac


async def test_me_returns_identity_from_token(nodb_client: AsyncClient) -> None:
    resp = await nodb_client.get("/v1/me", headers=bearer(make_token()))
    assert resp.status_code == 200
    assert resp.json() == {
        "sub": "user-a",
        "name": "Alice Example",
        "email": "alice@example.com",
        "roles": ["user"],
    }


async def test_me_requires_user_role(nodb_client: AsyncClient) -> None:
    token = make_token(realm_access={"roles": []})
    assert (await nodb_client.get("/v1/me", headers=bearer(token))).status_code == 403


async def test_me_and_hello_require_auth(nodb_client: AsyncClient) -> None:
    assert (await nodb_client.get("/v1/me")).status_code == 401
    assert (await nodb_client.get("/v1/hello")).status_code == 401


async def test_hello_without_database_is_503(nodb_client: AsyncClient) -> None:
    resp = await nodb_client.get("/v1/hello", headers=bearer(make_token()))
    assert resp.status_code == 503


@requires_postgres
@pytest.mark.usefixtures("clean_visits")
async def test_hello_first_and_second_visit(client: AsyncClient) -> None:
    first = await client.get("/v1/hello", headers=bearer(make_token()))
    assert first.status_code == 200
    body = first.json()
    assert body["visit_count"] == 1
    assert body["last_visit"] is None
    assert body["message"] == "Hello, Alice Example — this is your first visit"

    second = await client.get("/v1/hello", headers=bearer(make_token()))
    body2 = second.json()
    assert body2["visit_count"] == 2
    assert body2["last_visit"] is not None
    assert body2["message"] == f"Hello, Alice Example — last visit {body2['last_visit']}"


@requires_postgres
@pytest.mark.usefixtures("clean_visits")
async def test_hello_counts_are_per_subject(client: AsyncClient) -> None:
    for _ in range(3):
        await client.get("/v1/hello", headers=bearer(make_token(sub="user-a")))
    resp_b = await client.get(
        "/v1/hello", headers=bearer(make_token(sub="user-b", name="Bob", preferred_username="bob"))
    )
    assert resp_b.json()["visit_count"] == 1
    assert resp_b.json()["message"].startswith("Hello, Bob")
    resp_a = await client.get("/v1/hello", headers=bearer(make_token(sub="user-a")))
    assert resp_a.json()["visit_count"] == 4


@requires_postgres
@pytest.mark.usefixtures("clean_visits")
async def test_hello_falls_back_to_username_then_sub(client: AsyncClient) -> None:
    resp = await client.get("/v1/hello", headers=bearer(make_token(sub="u-x", name=None)))
    assert resp.json()["message"].startswith("Hello, alice")
    resp = await client.get(
        "/v1/hello", headers=bearer(make_token(sub="u-y", name=None, preferred_username=None))
    )
    assert resp.json()["message"].startswith("Hello, u-y")


@requires_postgres
@pytest.mark.usefixtures("clean_visits")
async def test_hello_rows_are_scoped_by_rls(client: AsyncClient) -> None:
    """Even if service code were wrong, RLS keeps user-b from seeing user-a's row."""
    await client.get("/v1/hello", headers=bearer(make_token(sub="user-a")))
    db = Database(pg_url("app_rw"))
    try:
        async with db.user_session("user-b") as session:
            rows = (await session.execute(text("SELECT owner_sub FROM visits"))).all()
        assert rows == []
    finally:
        await db.dispose()
