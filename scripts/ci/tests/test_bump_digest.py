"""T13: bump-digest.py rewrites only the image lines of one component in the stack files."""

import importlib.util
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "scripts/ci/bump-digest.py"
spec = importlib.util.spec_from_file_location("bump_digest", SCRIPT)
bump = importlib.util.module_from_spec(spec)
assert spec.loader
spec.loader.exec_module(bump)

D_OLD = "sha256:" + "0" * 64
D_NEW = "sha256:" + "a" * 64
D_OTHER = "sha256:" + "b" * 64


def stack_files(tmp_path: Path) -> list[Path]:
    edge = tmp_path / "edge/compose.yaml"
    core = tmp_path / "core/compose.yaml"
    edge.parent.mkdir()
    core.parent.mkdir()
    edge.write_text(
        "services:\n"
        f"  traefik:\n    image: ghcr.io/akshatauppinventure/traefik:sha-0000000@{D_OLD}\n"
        f"  frontend:\n    image: ghcr.io/akshatauppinventure/frontend:sha-1111111@{D_OTHER}\n"
    )
    core.write_text(
        "services:\n"
        f"  migrate:\n    image: ghcr.io/akshatauppinventure/backend:sha-0000000@{D_OLD}\n"
        "    command: [alembic, upgrade, head]\n"
        f"  backend:\n    image: ghcr.io/akshatauppinventure/backend:sha-0000000@{D_OLD}\n"
        f"  postgres:\n    image: ghcr.io/akshatauppinventure/postgres:sha-2222222@{D_OTHER}\n"
    )
    return [edge, core]


def test_rewrites_every_line_of_the_component_only(tmp_path: Path) -> None:
    edge, core = stack_files(tmp_path)
    changed = bump.bump("backend", "sha-abc1234", D_NEW, [edge, core])
    assert changed == [core]
    text = core.read_text()
    assert text.count(f"ghcr.io/akshatauppinventure/backend:sha-abc1234@{D_NEW}") == 2
    assert f"postgres:sha-2222222@{D_OTHER}" in text  # untouched
    assert "command: [alembic, upgrade, head]" in text
    assert edge.read_text().count(D_OLD) == 1  # other file untouched


def test_idempotent(tmp_path: Path) -> None:
    files = stack_files(tmp_path)
    bump.bump("traefik", "sha-abc1234", D_NEW, files)
    assert bump.bump("traefik", "sha-abc1234", D_NEW, files) == []


def test_rejects_bad_inputs(tmp_path: Path) -> None:
    files = stack_files(tmp_path)
    with pytest.raises(ValueError):
        bump.bump("backend", "latest", D_NEW, files)
    with pytest.raises(ValueError):
        bump.bump("backend", "sha-abc1234", "sha256:short", files)
    with pytest.raises(ValueError):
        bump.bump("nginx", "sha-abc1234", D_NEW, files)


def test_unknown_component_in_files_is_an_error(tmp_path: Path) -> None:
    files = stack_files(tmp_path)
    with pytest.raises(ValueError, match="no image line"):
        bump.bump("keycloak", "sha-abc1234", D_NEW, files)


def test_cli(tmp_path: Path) -> None:
    edge, core = stack_files(tmp_path)
    res = subprocess.run(
        [sys.executable, str(SCRIPT), "--component", "frontend", "--tag", "sha-abc1234", "--digest", D_NEW, str(edge), str(core)],
        capture_output=True, text=True, check=False,
    )
    assert res.returncode == 0, res.stderr
    assert "changed=" in res.stdout
    assert f"frontend:sha-abc1234@{D_NEW}" in edge.read_text()
