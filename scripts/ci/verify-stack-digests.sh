#!/usr/bin/env bash
# cosign-verifies every ghcr.io image reference in the GitOps stacks (ADR-0019 §4, T13).
# Placeholder digests (sha256:000...0, written by T16 for components never deployed yet) are
# reported and skipped; every other digest must carry a keyless signature from build-publish.yml on main.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
REPO="${REPO:-akshatauppinventure/web-app-test}"
IDENTITY="^https://github.com/${REPO}/.github/workflows/build-publish.yml@refs/heads/main$"
ISSUER="https://token.actions.githubusercontent.com"
status=0; n=0
while read -r ref; do
  [[ -z "$ref" ]] && continue
  n=$((n+1))
  image="${ref%%:*}"; digest="${ref##*@}"
  if [[ "$digest" == "sha256:$(printf '0%.0s' $(seq 1 64))" ]]; then echo "skip $ref (placeholder, never deployed)"; continue; fi
  if cosign verify --certificate-identity-regexp "$IDENTITY" --certificate-oidc-issuer "$ISSUER" "${image}@${digest}" >/dev/null 2>&1; then
    echo "ok   $ref"
  else
    echo "FAIL $ref is not signed by ${REPO} build-publish.yml on main"; status=1
  fi
done < <(grep -rhoE 'ghcr\.io/[a-z0-9-]+/[a-z0-9-]+:[^@[:space:]]+@sha256:[0-9a-f]{64}' infra/stacks infra/host/bootstrap | sort -u)
[[ $n -gt 0 ]] || { echo "FAIL: no ghcr.io references found"; exit 1; }
exit $status
