"""Application settings (ADR-0008 §5, ADR-0016).

Values come from environment variables or, for secrets, from files in the secrets
directory (``SECRETS_DIR``, default ``/run/secrets``; Compose mounts them there). Nothing secret has
a default. ``Settings`` is created once by the app factory and passed explicitly.
"""

import os
from pathlib import Path
from typing import Literal

from pydantic import Field, SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict

Environment = Literal["local", "ci", "poc", "production"]
LogLevel = Literal["DEBUG", "INFO", "WARNING", "ERROR"]


class Settings(BaseSettings):
    # secrets_dir is injected by load_settings() so that constructing Settings directly
    # (tests) never touches the filesystem.
    model_config = SettingsConfigDict(
        secrets_dir=None,
        env_file=None,
        extra="forbid",
        frozen=True,
    )

    environment: Environment = Field(default="poc", description="Deployment environment")
    log_level: LogLevel = "INFO"
    log_json: bool = True

    database_url: SecretStr | None = Field(
        default=None, description="SQLAlchemy URL, read from secrets dir or env"
    )

    # OIDC / JWT validation (ADR-0011 §3). None of these are secrets.
    oidc_issuer: str = Field(
        default="https://test-vinayak.duckdns.org/auth/realms/app",
        description="Expected `iss` claim (public issuer URL of the Keycloak realm)",
    )
    oidc_jwks_url: str = Field(
        default="http://keycloak:8080/auth/realms/app/protocol/openid-connect/certs",
        description="JWKS endpoint reached over the internal network",
    )
    oidc_audience: str = "api"
    oidc_authorized_party: str = "web-bff"
    oidc_algorithms: tuple[str, ...] = ("RS256", "ES256")
    oidc_leeway_seconds: int = 30
    jwks_min_refresh_seconds: float = 60.0

    @property
    def docs_enabled(self) -> bool:
        """OpenAPI docs are served only in the local environment (ADR-0008 §5)."""
        return self.environment == "local"


def load_settings() -> Settings:
    """Build Settings from the environment.

    The secrets directory comes from ``SECRETS_DIR`` (default ``/run/secrets``) and is only
    used when it exists, so local runs and tests don't warn about a missing directory.
    """
    secrets_dir = Path(os.environ.get("SECRETS_DIR", "/run/secrets"))
    if secrets_dir.is_dir():
        # pydantic-settings accepts _secrets_dir at runtime; pyright can't see it.
        return Settings(_secrets_dir=secrets_dir)  # pyright: ignore[reportCallIssue]
    return Settings()
