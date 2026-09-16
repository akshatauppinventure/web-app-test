#!/usr/bin/env bash
# Prints a JSON array of image components whose sources changed between two commits (T12).
# Usage: changed-components.sh <base-sha> <head-sha>   |   changed-components.sh --all
# A change to the build workflow itself or to this script rebuilds everything.
set -euo pipefail
ALL='["frontend","backend","keycloak","traefik","crowdsec","postgres"]'
if [[ "${1:-}" == "--all" ]]; then echo "$ALL"; exit 0; fi
BASE="${1:?base sha}"; HEAD="${2:?head sha}"
files="$(git diff --name-only "$BASE" "$HEAD")"
if grep -qE '^(\.github/workflows/build-publish\.yml|scripts/ci/changed-components\.sh|\.trivyignore)$' <<<"$files"; then echo "$ALL"; exit 0; fi
out=()
grep -qE '^frontend/'        <<<"$files" && out+=(frontend)
grep -qE '^backend/'         <<<"$files" && out+=(backend)
grep -qE '^infra/keycloak/'  <<<"$files" && out+=(keycloak)
grep -qE '^infra/traefik/'   <<<"$files" && out+=(traefik)
grep -qE '^infra/crowdsec/'  <<<"$files" && out+=(crowdsec)
grep -qE '^infra/postgres/'  <<<"$files" && out+=(postgres)
if (( ${#out[@]} == 0 )); then echo "[]"; else printf '%s\n' "${out[@]}" | jq -R . | jq -cs .; fi
