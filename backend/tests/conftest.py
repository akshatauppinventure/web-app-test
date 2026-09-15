"""Shared pytest fixtures for the backend test-suite."""

from collections.abc import AsyncIterator

import pytest
from httpx import ASGITransport, AsyncClient

from app.config import Settings
from app.main import create_app

pytest_plugins = ["tests.db_fixtures"]


def make_settings(**overrides: object) -> Settings:
    """Build Settings for tests without reading the environment or /run/secrets."""
    values: dict[str, object] = {"environment": "local"}
    values.update(overrides)
    return Settings.model_validate(values)


@pytest.fixture
def settings() -> Settings:
    return make_settings()


@pytest.fixture
async def client(settings: Settings) -> AsyncIterator[AsyncClient]:
    app = create_app(settings)
    async with (
        app.router.lifespan_context(app),
        AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac,
    ):
        yield ac
