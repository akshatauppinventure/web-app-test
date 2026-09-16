"""Alembic environment: async psycopg engine, migrations executed as `app_owner`.

The connection is made as `app_migrator` (member of `app_owner`); `SET ROLE app_owner`
makes every created object owned by `app_owner`, so `app_rw` is never the owner and RLS
cannot be bypassed by the runtime role (ADR-0009 §3, ADR-0011 §4).
"""

import asyncio
import os

from alembic import context
from sqlalchemy import Connection, pool, text
from sqlalchemy.ext.asyncio import async_engine_from_config

config = context.config


def resolve_url() -> str:
    """DATABASE_URL, else the file named by DATABASE_URL_FILE (Compose secret), else alembic.ini."""
    if url := os.environ.get("DATABASE_URL"):
        return url
    if url_file := os.environ.get("DATABASE_URL_FILE"):
        with open(url_file, encoding="utf-8") as fh:
            return fh.read().strip()
    if url := config.get_main_option("sqlalchemy.url"):
        return url
    msg = (
        "DATABASE_URL or DATABASE_URL_FILE (app_migrator connection) is required to run migrations"
    )
    raise RuntimeError(msg)


url = resolve_url()
config.set_main_option("sqlalchemy.url", url)

# No autogenerate: migrations are hand-written so RLS/grants are explicit.
target_metadata = None


def run_migrations_offline() -> None:
    context.configure(
        url=url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
        transaction_per_migration=True,
    )
    with context.begin_transaction():
        context.run_migrations()


def do_run_migrations(connection: Connection) -> None:
    # SET ROLE is session-scoped; commit it in its own transaction so Alembic starts clean.
    with connection.begin():
        connection.execute(text("SET ROLE app_owner"))
    context.configure(
        connection=connection,
        target_metadata=target_metadata,
        transaction_per_migration=True,
    )
    with context.begin_transaction():
        context.run_migrations()


async def run_migrations_online() -> None:
    connectable = async_engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )
    async with connectable.connect() as connection:
        await connection.run_sync(do_run_migrations)
    await connectable.dispose()


if context.is_offline_mode():
    run_migrations_offline()
else:
    asyncio.run(run_migrations_online())
