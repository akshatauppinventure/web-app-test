"""T09: the migrate job reads its connection URL from a secret file (DATABASE_URL_FILE)."""

import os
import subprocess
import sys
from pathlib import Path

from .db_fixtures import BACKEND_DIR, pg_url, requires_postgres

pytestmark = requires_postgres


def run_alembic(*args: str, env: dict[str, str]) -> subprocess.CompletedProcess[str]:
    full_env = {
        k: v for k, v in os.environ.items() if k not in ("DATABASE_URL", "DATABASE_URL_FILE")
    }
    full_env.update(env)
    return subprocess.run(  # noqa: S603 - fixed argv, test only
        [sys.executable, "-m", "alembic", *args],
        cwd=BACKEND_DIR,
        env=full_env,
        capture_output=True,
        text=True,
        check=False,
    )


def test_database_url_file_is_honoured(tmp_path: Path) -> None:
    url_file = tmp_path / "migrate_database_url"
    url_file.write_text(pg_url("app_migrator") + "\n")
    result = run_alembic("current", env={"DATABASE_URL_FILE": str(url_file)})
    assert result.returncode == 0, result.stderr


def test_missing_url_fails_loudly() -> None:
    result = run_alembic("current", env={})
    assert result.returncode != 0
    assert "DATABASE_URL" in result.stderr
