"""T01: settings come from env vars and secret files, never from hard-coded defaults."""

from pathlib import Path

import pytest
from pydantic import SecretStr

from app.config import Settings, load_settings


def test_environment_defaults_to_poc_and_docs_off() -> None:
    s = Settings()
    assert s.environment == "poc"
    assert s.docs_enabled is False


def test_local_environment_enables_docs() -> None:
    s = Settings(environment="local")
    assert s.docs_enabled is True


def test_secrets_are_read_from_secrets_dir(tmp_path: Path) -> None:
    (tmp_path / "database_url").write_text("postgresql+psycopg://u:p@h/db\n")
    s = Settings(_secrets_dir=tmp_path)  # pyright: ignore[reportCallIssue]
    assert s.database_url is not None
    assert s.database_url.get_secret_value() == "postgresql+psycopg://u:p@h/db"


def test_environment_variable_overrides(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("ENVIRONMENT", "local")
    monkeypatch.setenv("LOG_LEVEL", "DEBUG")
    monkeypatch.setenv("SECRETS_DIR", "/nonexistent-secrets-dir")
    s = load_settings()
    assert s.environment == "local"
    assert s.log_level == "DEBUG"


def test_secret_values_never_repr() -> None:
    s = Settings(database_url=SecretStr("postgresql+psycopg://u:hunter2@h/db"))
    assert "hunter2" not in repr(s)
    assert "hunter2" not in str(s.model_dump())


def test_load_settings_uses_secrets_dir_when_present(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    (tmp_path / "database_url").write_text("postgresql+psycopg://u:p@h/db")
    monkeypatch.setenv("SECRETS_DIR", str(tmp_path))
    s = load_settings()
    assert s.database_url is not None
    assert s.database_url.get_secret_value() == "postgresql+psycopg://u:p@h/db"
