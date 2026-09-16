"""Database fixtures for integration tests against `compose.test.yaml`.

Connection details come from ``TEST_PG_HOST``/``TEST_PG_PORT`` (default 127.0.0.1:55432).
The passwords are the test-only values in ``scripts/test/pg-secrets`` (not secrets).
Every fixture here skips, rather than fails, when Postgres is unreachable.
"""

import os
import socket
from collections.abc import AsyncIterator
from pathlib import Path

import pytest
from alembic import command
from alembic.config import Config
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncEngine, create_async_engine

TEST_PG_HOST = os.environ.get("TEST_PG_HOST", "127.0.0.1")
TEST_PG_PORT = int(os.environ.get("TEST_PG_PORT", "55432"))
TEST_PASSWORDS = {
    "app_migrator": "test-only-app-migrator",
    "app_rw": "test-only-app-rw",
    "keycloak": "test-only-keycloak-db",
    "postgres": "test-only-postgres-superuser",
}
BACKEND_DIR = Path(__file__).resolve().parents[1]


def pg_url(role: str, database: str = "app") -> str:
    return f"postgresql+psycopg://{role}:{TEST_PASSWORDS[role]}@{TEST_PG_HOST}:{TEST_PG_PORT}/{database}"


def postgres_available() -> bool:
    if os.environ.get("TEST_PG_SKIP") == "1":
        return False
    try:
        with socket.create_connection((TEST_PG_HOST, TEST_PG_PORT), timeout=1):
            return True
    except OSError:
        return False


_PG_AVAILABLE = postgres_available()
if os.environ.get("TEST_PG_REQUIRED") == "1" and not _PG_AVAILABLE:  # CI must never silently skip
    msg = "TEST_PG_REQUIRED=1 but Postgres is not reachable"
    raise RuntimeError(msg)

requires_postgres = pytest.mark.skipif(
    not _PG_AVAILABLE,
    reason="Postgres not reachable; run `docker compose -f compose.test.yaml up -d --wait`",
)


def alembic_config(url: str) -> Config:
    cfg = Config(str(BACKEND_DIR / "alembic.ini"))
    cfg.set_main_option("script_location", str(BACKEND_DIR / "alembic"))
    cfg.set_main_option("sqlalchemy.url", url)
    return cfg


def migrate(direction: str) -> None:
    cfg = alembic_config(pg_url("app_migrator"))
    if direction == "head":
        command.upgrade(cfg, "head")
    else:
        command.downgrade(cfg, "base")


@pytest.fixture(scope="session")
def migrated_db() -> None:
    """Apply all migrations once per session as app_migrator (leaves schema in place)."""
    migrate("base")
    migrate("head")


@pytest.fixture
async def rw_engine(migrated_db: None) -> AsyncIterator[AsyncEngine]:
    engine = create_async_engine(pg_url("app_rw"), pool_size=2, max_overflow=0)
    try:
        yield engine
    finally:
        await engine.dispose()


@pytest.fixture
async def clean_visits(migrated_db: None) -> AsyncIterator[None]:
    """Truncate `visits` before and after a test, as the owner (via app_migrator)."""
    engine = create_async_engine(pg_url("app_migrator"), pool_size=1, max_overflow=0)

    async def truncate() -> None:
        async with engine.begin() as conn:
            await conn.execute(text("SET ROLE app_owner"))
            await conn.execute(text("TRUNCATE visits"))

    await truncate()
    try:
        yield
    finally:
        await truncate()
        await engine.dispose()
