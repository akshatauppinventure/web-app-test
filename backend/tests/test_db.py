"""T02: engine/session helpers and the readiness probe."""

from httpx import ASGITransport, AsyncClient
from sqlalchemy import text

from app.db import Database
from app.main import create_app

from .conftest import make_settings
from .db_fixtures import pg_url, requires_postgres


async def test_readyz_is_503_without_a_database(client: AsyncClient) -> None:
    resp = await client.get("/readyz")
    assert resp.status_code == 503
    assert resp.json() == {"status": "unavailable"}


async def test_readyz_is_503_when_database_unreachable() -> None:
    settings = make_settings(database_url="postgresql+psycopg://x:y@127.0.0.1:1/app")
    app = create_app(settings)
    async with (
        app.router.lifespan_context(app),
        AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac,
    ):
        resp = await ac.get("/readyz")
    assert resp.status_code == 503
    assert resp.json() == {"status": "unavailable"}


@requires_postgres
async def test_readyz_is_200_with_database() -> None:
    settings = make_settings(database_url=pg_url("app_rw"))
    app = create_app(settings)
    async with (
        app.router.lifespan_context(app),
        AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac,
    ):
        resp = await ac.get("/readyz")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok"}


@requires_postgres
async def test_database_user_session_sets_context() -> None:
    db = Database(pg_url("app_rw"))
    try:
        async with db.user_session("sub-123") as session:
            value = (
                await session.execute(text("SELECT current_setting('app.user_id', true)"))
            ).scalar_one()
        assert value == "sub-123"
    finally:
        await db.dispose()
