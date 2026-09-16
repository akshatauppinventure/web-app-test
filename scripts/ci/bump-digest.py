#!/usr/bin/env python3
"""Rewrite the image reference of one component in the GitOps stack files (PLAN T13, ADR-0018).

Only lines of the form ``image: ghcr.io/<owner>/<component>:<tag>@sha256:<digest>`` for the given
component are touched; everything else (including other components) is left byte-for-byte intact.
Usage: bump-digest.py --component backend --tag sha-<sha> --digest sha256:<64 hex> [files...]
Prints ``changed=<comma-separated files>`` (empty when nothing changed). Exit 0 on success.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OWNER = "akshatauppinventure"
COMPONENTS = ("frontend", "backend", "keycloak", "traefik", "crowdsec", "postgres")
DEFAULT_FILES = [ROOT / "infra/stacks/edge/compose.yaml", ROOT / "infra/stacks/core/compose.yaml"]


def bump(component: str, tag: str, digest: str, files: list[Path]) -> list[Path]:
    if component not in COMPONENTS:
        raise ValueError(f"unknown component {component!r}; expected one of {COMPONENTS}")
    if not re.fullmatch(r"sha-[0-9a-f]{7,40}", tag):
        raise ValueError(f"tag must look like sha-<git sha>, got {tag!r}")
    if not re.fullmatch(r"sha256:[0-9a-f]{64}", digest):
        raise ValueError(f"digest must be sha256:<64 hex>, got {digest!r}")
    pattern = re.compile(
        rf"^(?P<indent>\s*image:\s*)ghcr\.io/{re.escape(OWNER)}/{re.escape(component)}:[^@\s]+@sha256:[0-9a-f]{{64}}\s*$",
        re.MULTILINE,
    )
    replacement = rf"\g<indent>ghcr.io/{OWNER}/{component}:{tag}@{digest}"
    changed: list[Path] = []
    matched_anywhere = False
    for path in files:
        text = path.read_text()
        new_text, n = pattern.subn(replacement, text)
        matched_anywhere = matched_anywhere or n > 0
        if n and new_text != text:
            path.write_text(new_text)
            changed.append(path)
    if not matched_anywhere:
        raise ValueError(f"no image line for component {component!r} in {[str(f) for f in files]}")
    return changed


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--component", required=True)
    ap.add_argument("--tag", required=True)
    ap.add_argument("--digest", required=True)
    ap.add_argument("files", nargs="*", type=Path)
    args = ap.parse_args(argv)
    files = args.files or DEFAULT_FILES
    try:
        changed = bump(args.component, args.tag, args.digest, files)
    except ValueError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    print("changed=" + ",".join(str(p) for p in changed))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
