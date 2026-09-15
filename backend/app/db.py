"""Async database access with per-transaction Row-Level Security context (ADR-0011 §4.3).

Every request that touches user data runs inside ``Database.user_session(sub)``, which
opens a transaction and sets ``app.user_id`` *transaction-locally* (``set_config(..., true)``)
so the RLS policies in the migrations scope every statement to the caller. Nothing here
accepts a user id from the client; the caller passes the verified token ``sub``.
"""

import asyncio
from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager

from sqlalchemy import text
from sqlalchemy.ext.asyncio import (
    AsyncConnection,
    AsyncEngine,
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)

_SET_RLS_USER = text("SELECT set_config('app.user_id', :sub, true)")


async def set_rls_user(conn: AsyncConnection | AsyncSession, sub: str) -> None:
    """Set the RLS user context for the *current transaction* only."""
    if not sub:
        msg = "RLS user context must be a non-empty subject"
        raise ValueError(msg)
    await conn.execute(_SET_RLS_USER, {"sub": sub})


class Database:
    """Engine + session factory. One instance per app, created in the lifespan."""

    def __init__(self, url: str, *, pool_size: int = 5, max_overflow: int = 5) -> None:
        self.engine: AsyncEngine = create_async_engine(
            url,
            pool_size=pool_size,
            max_overflow=max_overflow,
            pool_pre_ping=True,
            pool_recycle=1800,
            connect_args={"connect_timeout": 5},
        )
        self._sessions = async_sessionmaker(self.engine, expire_on_commit=False, autoflush=False)

    @asynccontextmanager
    async def user_session(self, sub: str) -> AsyncGenerator[AsyncSession]:
        """A transaction scoped to ``sub``; commits on success, rolls back on error."""
        async with self._sessions() as session, session.begin():
            await set_rls_user(session, sub)
            yield session

    ping_timeout: float = 2.0

    async def ping(self) -> bool:
        """Readiness probe: a trivial round-trip within ``ping_timeout`` seconds."""
        try:
            async with asyncio.timeout(self.ping_timeout), self.engine.connect() as conn:
                await conn.execute(text("SELECT 1"))
        except Exception:
            return False
        return True

    async def dispose(self) -> None:
        await self.engine.dispose()
