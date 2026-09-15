"""Structured JSON logging (ADR-0008 §5): never log tokens, secrets or personal data."""

import logging
import sys
from collections.abc import MutableMapping
from typing import Any

import structlog

from app.config import LogLevel

_SENSITIVE_KEYS = frozenset(
    {
        "authorization",
        "cookie",
        "set-cookie",
        "set_cookie",
        "password",
        "secret",
        "token",
        "access_token",
        "refresh_token",
        "id_token",
        "client_secret",
        "database_url",
    }
)
_REDACTED = "[REDACTED]"


def redact_sensitive(
    _logger: object, _method: str, event_dict: MutableMapping[str, Any]
) -> MutableMapping[str, Any]:
    """structlog processor: replace values of sensitive keys."""
    for key in list(event_dict):
        if key.lower() in _SENSITIVE_KEYS:
            event_dict[key] = _REDACTED
    return event_dict


def configure_logging(level: LogLevel = "INFO", *, json_output: bool = True) -> None:
    """Configure stdlib + structlog once. Safe to call repeatedly (tests)."""
    numeric = logging.getLevelNamesMapping()[level]
    logging.basicConfig(level=numeric, stream=sys.stdout, format="%(message)s", force=True)

    renderer = (
        structlog.processors.JSONRenderer()
        if json_output
        else structlog.dev.ConsoleRenderer(colors=False)
    )
    structlog.configure(
        processors=[
            structlog.contextvars.merge_contextvars,
            structlog.processors.add_log_level,
            structlog.processors.TimeStamper(fmt="iso", utc=True),
            redact_sensitive,
            structlog.processors.StackInfoRenderer(),
            structlog.processors.format_exc_info,
            renderer,
        ],
        wrapper_class=structlog.make_filtering_bound_logger(numeric),
        logger_factory=structlog.PrintLoggerFactory(sys.stdout),
        cache_logger_on_first_use=False,
    )
