#!/usr/bin/env bash
# Verifies every `ports:` entry in compose files against infra/policy/published-ports.txt
# (ADR-0014). Stack files (infra/stacks/**) must match the allowlist exactly; every other compose
# file may only bind 127.0.0.1. A `ports:` entry without a host IP is always rejected.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# Required stack variables (`${VAR:?}`) get placeholders so `config` can run without Portainer.
export ACME_EMAIL="${ACME_EMAIL:-ci-placeholder@example.com}" GOOGLE_CLIENT_ID="${GOOGLE_CLIENT_ID:-ci-placeholder}"
ALLOWLIST="$ROOT/infra/policy/published-ports.txt"
status=0

allowed_entries="$(grep -vE '^[[:space:]]*(#|$)' "$ALLOWLIST")"

check_file() {
  local file="$1" scope="$2" profiles=(--profile '*')
  local json
  json="$(cd "$ROOT" && docker compose -f "$file" "${profiles[@]}" config --format json 2>/dev/null)" || { echo "FAIL $file: docker compose config failed"; status=1; return; }
  while IFS=$'\t' read -r service host_ip published target protocol; do
    [[ -z "$service" ]] && continue
    local entry="${host_ip}:${published}/${protocol}"
    if [[ -z "$host_ip" || "$host_ip" == "null" ]]; then
      echo "FAIL $file: $service publishes $published->$target without a host IP"; status=1; continue
    fi
    if [[ "$scope" == "stack" ]]; then
      if grep -qx -- "$entry" <<<"$allowed_entries"; then
        echo "ok   $file: $service $entry"
      else
        echo "FAIL $file: $service publishes $entry, not in $ALLOWLIST"; status=1
      fi
    else
      if [[ "$host_ip" == "127.0.0.1" ]]; then
        echo "ok   $file: $service $entry (loopback)"
      else
        echo "FAIL $file: $service publishes $entry; non-stack compose files may only bind 127.0.0.1"; status=1
      fi
    fi
  done < <(jq -r '.services | to_entries[] | .key as $s | (.value.ports // [])[] | [$s, (.host_ip // "null"), (.published|tostring), (.target|tostring), (.protocol // "tcp")] | @tsv' <<<"$json")
}

cd "$ROOT"
while IFS= read -r f; do
  case "$f" in
    infra/stacks/*) check_file "$f" stack ;;
    *) check_file "$f" other ;;
  esac
done < <(git ls-files 'compose*.yaml' 'compose*.yml' 'infra/stacks/*/compose.yaml' 'infra/host/bootstrap/*.compose.yaml' | sort -u)
exit $status
