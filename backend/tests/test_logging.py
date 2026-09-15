"""T01: structured JSON logging with sensitive keys redacted (ADR-0008 §5)."""

import json

import pytest
import structlog

from app.logging import configure_logging


def test_logs_are_json_and_redact_sensitive_keys(capsys: pytest.CaptureFixture[str]) -> None:
    configure_logging(level="INFO", json_output=True)
    log = structlog.get_logger("test")
    log.info("hello", user="u1", authorization="Bearer abc", password="pw", cookie="c=1")
    out = capsys.readouterr().out.strip().splitlines()[-1]
    record = json.loads(out)
    assert record["event"] == "hello"
    assert record["user"] == "u1"
    assert record["level"] == "info"
    assert "timestamp" in record
    assert record["authorization"] == "[REDACTED]"
    assert record["password"] == "[REDACTED]"
    assert record["cookie"] == "[REDACTED]"
    assert "abc" not in out


def test_log_level_filters(capsys: pytest.CaptureFixture[str]) -> None:
    configure_logging(level="WARNING", json_output=True)
    structlog.get_logger("t").info("dropped")
    assert capsys.readouterr().out.strip() == ""
