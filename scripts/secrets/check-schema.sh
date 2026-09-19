#!/usr/bin/env bash
# Cross-checks infra/secrets/SCHEMA.md against every secret referenced by the stacks, the Portainer
# bootstrap files and the host scripts (CI, T19). Fails on names missing from the schema or unused.
# shellcheck disable=SC2016  # backticks inside grep patterns are literal
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
schema="$(grep -oE '^\| `[a-z0-9_-]+`' infra/secrets/SCHEMA.md | tr -d '|` ' | sort -u)"
referenced="$( { grep -rhoE 'file: /etc/app/secrets/[a-z0-9_]+' infra/stacks infra/host/bootstrap | sed 's#.*/##';
                 grep -rhoE '\$SECRETS/[a-z0-9_]+' infra/host/scripts | sed 's#.*/##'; } | sort -u)"
status=0
while read -r n; do [[ -z "$n" ]] && continue; grep -qx "$n" <<<"$schema" || { echo "FAIL: '$n' is referenced but missing from SCHEMA.md"; status=1; }; done <<<"$referenced"
while read -r n; do
  [[ -z "$n" ]] && continue
  grep -qx "$n" <<<"$referenced" || { echo "FAIL: '$n' is in SCHEMA.md but nothing references it"; status=1; }
done <<<"$schema"
# every generated file must cover its host's schema entries
for h in edge core; do
  tmp="$(mktemp)"; scripts/secrets/gen-secrets.sh "$h" "$tmp" >/dev/null
  gen="$(grep -oE '^[a-z0-9_-]+' "$tmp" | sort -u)"; rm -f "$tmp"
  expected="$(awk "/^## $h/{f=1;next} /^## /{f=0} f" infra/secrets/SCHEMA.md | grep -oE '^\| `[a-z0-9_-]+`' | tr -d '|` ' | sort -u)"
  diff <(echo "$expected") <(echo "$gen") >/dev/null || { echo "FAIL: gen-secrets.sh $h and SCHEMA.md differ:"; diff <(echo "$expected") <(echo "$gen") || true; status=1; }
done
(( status )) || echo "ok: SCHEMA.md matches $(wc -l <<<"$referenced" | tr -d ' ') referenced secrets and both generators"
exit $status
