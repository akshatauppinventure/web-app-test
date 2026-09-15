"""T02: migrations, least-privilege roles and Row-Level Security (ADR-0009 §3-4, ADR-0011 §4)."""

from datetime import UTC, datetime

import pytest
from sqlalchemy import text
from sqlalchemy.exc import DBAPIError, OperationalError, ProgrammingError
from sqlalchemy.ext.asyncio import AsyncEngine, create_async_engine

from app.db import set_rls_user

from .db_fixtures import migrate, pg_url, requires_postgres

pytestmark = requires_postgres

INSERT = text(
    "INSERT INTO visits (owner_sub, display_name, last_visit, visit_count)"
    " VALUES (:sub, :name, :ts, 1)"
)
NOW = datetime.now(tz=UTC)


async def insert_as(engine: AsyncEngine, sub: str, name: str = "n") -> None:
    async with engine.begin() as conn:
        await set_rls_user(conn, sub)
        await conn.execute(INSERT, {"sub": sub, "name": name, "ts": NOW})


# --- migrations -------------------------------------------------------------------------


@pytest.mark.usefixtures("migrated_db")
async def test_migration_creates_visits_with_forced_rls(rw_engine: AsyncEngine) -> None:
    async with rw_engine.connect() as conn:
        row = (
            await conn.execute(
                text(
                    "SELECT relrowsecurity, relforcerowsecurity, pg_get_userbyid(relowner)"
                    " FROM pg_class WHERE relname = 'visits'"
                )
            )
        ).one()
    assert row == (True, True, "app_owner")


def test_migration_downgrade_and_upgrade_roundtrip() -> None:
    migrate("base")
    migrate("head")
    migrate("base")
    migrate("head")


# --- RLS behaviour ----------------------------------------------------------------------


@pytest.mark.usefixtures("clean_visits")
async def test_users_only_see_their_own_rows(rw_engine: AsyncEngine) -> None:
    await insert_as(rw_engine, "user-a", "Alice")
    await insert_as(rw_engine, "user-b", "Bob")

    async with rw_engine.begin() as conn:
        await set_rls_user(conn, "user-a")
        rows = (await conn.execute(text("SELECT owner_sub FROM visits ORDER BY 1"))).scalars().all()
    assert rows == ["user-a"]


@pytest.mark.usefixtures("clean_visits")
async def test_update_and_delete_cannot_touch_other_users_rows(rw_engine: AsyncEngine) -> None:
    await insert_as(rw_engine, "user-a")
    async with rw_engine.begin() as conn:
        await set_rls_user(conn, "user-b")
        upd = await conn.execute(
            text("UPDATE visits SET visit_count = 99 WHERE owner_sub = 'user-a'")
        )
        dele = await conn.execute(text("DELETE FROM visits WHERE owner_sub = 'user-a'"))
    assert (upd.rowcount, dele.rowcount) == (0, 0)

    async with rw_engine.begin() as conn:
        await set_rls_user(conn, "user-a")
        count = (await conn.execute(text("SELECT visit_count FROM visits"))).scalar_one()
    assert count == 1


@pytest.mark.usefixtures("clean_visits")
async def test_cannot_insert_a_row_for_another_user(rw_engine: AsyncEngine) -> None:
    with pytest.raises(DBAPIError, match="row-level security"):
        async with rw_engine.begin() as conn:
            await set_rls_user(conn, "user-b")
            await conn.execute(INSERT, {"sub": "user-a", "name": "x", "ts": NOW})


@pytest.mark.usefixtures("clean_visits")
async def test_no_context_yields_no_rows_and_no_writes(rw_engine: AsyncEngine) -> None:
    await insert_as(rw_engine, "user-a")
    async with rw_engine.begin() as conn:
        rows = (await conn.execute(text("SELECT owner_sub FROM visits"))).all()
    assert rows == []
    with pytest.raises(DBAPIError, match="row-level security"):
        async with rw_engine.begin() as conn:
            await conn.execute(INSERT, {"sub": "user-c", "name": "x", "ts": NOW})


@pytest.mark.usefixtures("clean_visits")
async def test_context_is_transaction_local(rw_engine: AsyncEngine) -> None:
    await insert_as(rw_engine, "user-a")
    async with rw_engine.connect() as conn:
        async with conn.begin():
            await set_rls_user(conn, "user-a")
            assert (await conn.execute(text("SELECT count(*) FROM visits"))).scalar_one() == 1
        # same connection, new transaction, no context -> fail closed
        async with conn.begin():
            assert (await conn.execute(text("SELECT count(*) FROM visits"))).scalar_one() == 0


# --- privilege boundaries ---------------------------------------------------------------


@pytest.mark.usefixtures("migrated_db")
async def test_app_rw_cannot_escalate_or_bypass_rls(rw_engine: AsyncEngine) -> None:
    async with rw_engine.connect() as conn:
        flags = (
            await conn.execute(
                text(
                    "SELECT rolsuper, rolbypassrls, rolcreaterole, rolcreatedb"
                    " FROM pg_roles WHERE rolname = current_user"
                )
            )
        ).one()
        assert flags == (False, False, False, False)

    for stmt in (
        "SET ROLE app_owner",
        "SET ROLE app_migrator",
        "SET ROLE postgres",
        "ALTER TABLE visits DISABLE ROW LEVEL SECURITY",
        "ALTER TABLE visits NO FORCE ROW LEVEL SECURITY",
        "DROP POLICY visits_owner_only ON visits",
        "CREATE TABLE sneaky (id int)",
        "ALTER ROLE app_rw BYPASSRLS",
        "SET session_authorization = 'postgres'",
    ):
        with pytest.raises(ProgrammingError):
            async with rw_engine.begin() as conn:
                await conn.execute(text(stmt))


@pytest.mark.usefixtures("migrated_db")
async def test_app_rw_has_only_dml_on_visits(rw_engine: AsyncEngine) -> None:
    async with rw_engine.connect() as conn:
        privs = (
            (
                await conn.execute(
                    text(
                        "SELECT privilege_type FROM information_schema.role_table_grants"
                        " WHERE grantee = 'app_rw' AND table_name = 'visits' ORDER BY 1"
                    )
                )
            )
            .scalars()
            .all()
        )
    assert privs == ["DELETE", "INSERT", "SELECT", "UPDATE"]


async def test_keycloak_role_cannot_connect_to_app_db() -> None:
    engine = create_async_engine(pg_url("keycloak", "app"), pool_size=1, max_overflow=0)
    try:
        with pytest.raises(OperationalError, match="permission denied"):
            async with engine.connect():
                pass
    finally:
        await engine.dispose()


async def test_app_rw_cannot_connect_to_keycloak_db() -> None:
    engine = create_async_engine(pg_url("app_rw", "keycloak"), pool_size=1, max_overflow=0)
    try:
        with pytest.raises(OperationalError, match="permission denied"):
            async with engine.connect():
                pass
    finally:
        await engine.dispose()


@pytest.mark.usefixtures("migrated_db")
async def test_app_rw_session_settings_applied(rw_engine: AsyncEngine) -> None:
    async with rw_engine.connect() as conn:
        st = (await conn.execute(text("SHOW statement_timeout"))).scalar_one()
        idle = (await conn.execute(text("SHOW idle_in_transaction_session_timeout"))).scalar_one()
        enc = (await conn.execute(text("SHOW password_encryption"))).scalar_one()
    assert (st, idle, enc) == ("15s", "30s", "scram-sha-256")
