#!/usr/bin/env python3
"""Assert every service in infra/stacks/*/compose.yaml follows the container hardening baseline.

Checks (ADR-0005, ADR-0014): explicit non-root ``user`` (or a justified exception), ``read_only``,
``cap_drop: [ALL]`` with ``cap_add`` only from the exception list, ``no-new-privileges``, a
healthcheck (one-shot jobs exempt), memory and pids limits, a restart policy, no ``privileged``,
no Docker socket / host network / host PID, images pinned by digest, and ``logging`` set.
Usage: check-hardening.py [compose files...]  (default: infra/stacks/*/compose.yaml)
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path

import yaml  # PyYAML: `uv run --with pyyaml` locally, preinstalled on GitHub runners

ROOT = Path(__file__).resolve().parents[2]
EXCEPTIONS_FILE = ROOT / "infra/policy/hardening-exceptions.yaml"
DIGEST_RE = re.compile(r"@sha256:[0-9a-f]{64}$")


def compose_config(path: Path) -> dict:
    env = {**os.environ}
    env.setdefault("ACME_EMAIL", "ci-placeholder@example.com")
    env.setdefault("GOOGLE_CLIENT_ID", "ci-placeholder")
    out = subprocess.run(
        ["docker", "compose", "-f", str(path), "--profile", "*", "config", "--format", "json"],
        check=True,
        capture_output=True,
        text=True,
        cwd=ROOT,
        env=env,
    ).stdout
    return json.loads(out)


def check_service(stack: str, name: str, svc: dict, exc: dict) -> list[str]:
    errors: list[str] = []
    ex = exc.get(f"{stack}/{name}", {})
    one_shot = svc.get("restart") in ("no", None) and svc.get("command") is not None

    if not DIGEST_RE.search(svc.get("image", "")):
        errors.append("image is not pinned by @sha256 digest")
    user = str(svc.get("user", ""))
    if not user:
        errors.append("no explicit `user:`")
    elif user.split(":")[0] in ("0", "root") and not ex.get("root"):
        errors.append("runs as root without an exception")
    if svc.get("read_only") is not True:
        errors.append("read_only is not true")
    if [c.upper() for c in svc.get("cap_drop", [])] != ["ALL"]:
        errors.append("cap_drop must be exactly [ALL]")
    allowed_caps = {c.upper() for c in ex.get("cap_add", [])}
    extra = {c.upper() for c in svc.get("cap_add", [])} - allowed_caps
    if extra:
        errors.append(f"cap_add not allowed: {sorted(extra)}")
    if "no-new-privileges:true" not in [str(o) for o in svc.get("security_opt", [])]:
        errors.append("security_opt lacks no-new-privileges:true")
    if svc.get("privileged"):
        errors.append("privileged is set")
    if svc.get("network_mode") == "host" or svc.get("pid") == "host":
        errors.append("host network/pid namespace")
    for vol in svc.get("volumes", []):
        src = vol.get("source", "") if isinstance(vol, dict) else str(vol)
        if "docker.sock" in src:
            errors.append("mounts the Docker socket")
    if not one_shot and not ex.get("no_healthcheck") and "healthcheck" not in svc:
        errors.append("no healthcheck")
    limits = (svc.get("deploy") or {}).get("resources", {}).get("limits", {})
    if not svc.get("mem_limit") and not limits.get("memory"):
        errors.append("no memory limit")
    if not svc.get("pids_limit") and not limits.get("pids"):
        errors.append("no pids_limit")
    if "restart" not in svc:
        errors.append("no restart policy")
    if "logging" not in svc:
        errors.append("no logging configuration")
    return errors


def main(argv: list[str]) -> int:
    files = [Path(a) for a in argv] or sorted(ROOT.glob("infra/stacks/*/compose.yaml"))
    exceptions = yaml.safe_load(EXCEPTIONS_FILE.read_text()) or {}
    status = 0
    for f in files:
        cfg = compose_config(f)
        stack = f.parent.name
        for name, svc in sorted(cfg.get("services", {}).items()):
            errs = check_service(stack, name, svc, exceptions)
            if errs:
                status = 1
                for e in errs:
                    print(f"FAIL {stack}/{name}: {e}")
            else:
                print(f"ok   {stack}/{name}")
    return status


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
