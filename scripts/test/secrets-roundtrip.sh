#!/usr/bin/env bash
# T19 test: throwaway age key, generate both hosts' secrets, encrypt/decrypt round trip with sops,
# shared values consistent, dry-run push prints paths only, schema check passes.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok: $*"; }
age-keygen -o "$work/key.txt" >/dev/null 2>&1
pub="$(grep -oE 'age1[0-9a-z]+' "$work/key.txt" | head -1)"
export SOPS_AGE_KEY_FILE="$work/key.txt"
cat > "$work/sops.yaml" <<YAML
creation_rules:
  - path_regex: .*
    age: "$pub"
YAML
scripts/secrets/gen-secrets.sh core "$work/core.yaml" >/dev/null
scripts/secrets/gen-secrets.sh edge "$work/edge.yaml" --shared-from "$work/core.yaml" >/dev/null
for h in edge core; do
  sops --config "$work/sops.yaml" --encrypt --input-type yaml --output-type yaml "$work/$h.yaml" > "$work/$h.sops.yaml"
  grep -q "ENC\[AES256_GCM" "$work/$h.sops.yaml" || fail "$h not encrypted"
  if grep -qE 'postgresql\+psycopg://app_rw:[A-Za-z0-9]{40}@' "$work/$h.sops.yaml"; then fail "$h leaks a value"; fi
  # compare values (sops re-serializes YAML, so a byte diff is meaningless)
  sops --config "$work/sops.yaml" -d --output-type json "$work/$h.sops.yaml" > "$work/$h.dec.json"
  python3 - "$work/$h.yaml" "$work/$h.dec.json" <<'PY2' || fail "$h round trip differs"
import json, sys
plain = {}
for line in open(sys.argv[1]):
    if ":" in line and not line.startswith("#"):
        k, v = line.split(":", 1); plain[k.strip()] = v.strip().strip('"')
dec = json.load(open(sys.argv[2]))
assert plain == dec, (set(plain) ^ set(dec), [k for k in plain if plain[k] != dec.get(k)])
PY2
done
pass "encrypt/decrypt round trip for edge and core with a throwaway age key"
[[ "$(grep '^web_bff_client_secret' "$work/edge.yaml")" == "$(grep '^web_bff_client_secret' "$work/core.yaml")" ]] || fail "web_bff_client_secret differs between hosts"
[[ "$(grep '^portainer_agent_secret' "$work/edge.yaml")" == "$(grep '^portainer_agent_secret' "$work/core.yaml")" ]] || fail "portainer_agent_secret differs between hosts"
pass "shared values consistent across hosts (--shared-from)"
out="$(SOPS_CONFIG="$work/sops.yaml" SECRETS_FILE="$work/core.sops.yaml" scripts/secrets/secrets-push.sh core --dry-run)"
grep -q "restic_password -> /etc/app/secrets/restic_password (owner 0, mode 0400)" <<<"$out" || fail "dry run output unexpected: $out"
! grep -qi "wireguard" <<<"$out" || fail "dry run still lists WireGuard secrets"
grep -q "would push core secrets to webapptest-core" <<<"$out" || fail "default SSH target is not the webapptest-core alias: $out"
grep -qE '[A-Za-z0-9]{40}' <<<"$out" && fail "dry run printed a value" || true
pass "secrets-push --dry-run prints destinations and modes only"
scripts/secrets/check-schema.sh
echo "ALL SECRETS CHECKS PASSED"
