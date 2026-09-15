"""ASGI app factory."""

from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager

import structlog
from fastapi import FastAPI

from app.api import health
from app.config import Settings, load_settings
from app.db import Database
from app.logging import configure_logging


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or load_settings()
    configure_logging(settings.log_level, json_output=settings.log_json)
    log = structlog.get_logger("app")

    @asynccontextmanager
    async def lifespan(app: FastAPI) -> AsyncGenerator[None]:
        log.info("startup", environment=settings.environment)
        db = Database(settings.database_url.get_secret_value()) if settings.database_url else None
        app.state.db = db
        try:
            yield
        finally:
            if db is not None:
                await db.dispose()
            log.info("shutdown")

    docs = settings.docs_enabled
    app = FastAPI(
        title="web-app-test API",
        version="0.1.0",
        lifespan=lifespan,
        docs_url="/docs" if docs else None,
        redoc_url="/redoc" if docs else None,
        openapi_url="/openapi.json" if docs else None,
    )
    app.state.settings = settings
    app.include_router(health.router)
    return app


app = create_app()
