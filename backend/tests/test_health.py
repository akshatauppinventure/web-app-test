"""T01: liveness/readiness endpoints and OpenAPI exposure rules (ADR-0008 §5)."""

from httpx import ASGITransport, AsyncClient

from app.main import create_app

from .conftest import make_settings


async def test_healthz_returns_200_without_dependencies(client: AsyncClient) -> None:
    resp = await client.get("/healthz")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok"}


async def test_readyz_stub_returns_200(client: AsyncClient) -> None:
    resp = await client.get("/readyz")
    assert resp.status_code == 200
    assert resp.json()["status"] == "ok"


async def test_docs_available_in_local_environment(client: AsyncClient) -> None:
    assert (await client.get("/docs")).status_code == 200
    assert (await client.get("/openapi.json")).status_code == 200


async def test_docs_disabled_outside_local_environment() -> None:
    app = create_app(make_settings(environment="poc"))
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        for path in ("/docs", "/redoc", "/openapi.json"):
            assert (await ac.get(path)).status_code == 404, path
        assert (await ac.get("/healthz")).status_code == 200


async def test_unknown_route_does_not_leak_internals(client: AsyncClient) -> None:
    resp = await client.get("/definitely-not-here")
    assert resp.status_code == 404
    assert resp.json() == {"detail": "Not Found"}
    assert "server" not in {k.lower() for k in resp.headers}
