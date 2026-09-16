#!/usr/bin/env bash
# `docker compose config` for every compose file in the repo (all profiles).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# Required stack variables (`${VAR:?}`) get placeholders so `config` can run without Portainer.
export ACME_EMAIL="${ACME_EMAIL:-ci-placeholder@example.com}" GOOGLE_CLIENT_ID="${GOOGLE_CLIENT_ID:-ci-placeholder}"
cd "$ROOT"
status=0
while IFS= read -r f; do
  if docker compose -f "$f" --profile '*' config -q; then echo "ok   $f"; else echo "FAIL $f"; status=1; fi
done < <(git ls-files 'compose*.yaml' 'compose*.yml' 'infra/stacks/*/compose.yaml' 'infra/host/bootstrap/*.compose.yaml' | sort -u)
exit $status
