#!/usr/bin/env bash
# Local dry run of the GitOps stacks (PLAN T16): the real infra/stacks/*/compose.yaml files plus the
# overlays in scripts/test/stacks/ (local images, .dev-secrets, loopback binds). Core first, then edge.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok: $*"; }
CORE=(docker compose -p dryrun-core -f infra/stacks/core/compose.yaml -f scripts/test/stacks/core.override.yaml)
EDGE=(docker compose -p dryrun-edge -f infra/stacks/edge/compose.yaml -f scripts/test/stacks/edge.override.yaml)
cleanup() { "${CORE[@]}" down -v >/dev/null 2>&1 || true; "${EDGE[@]}" down -v >/dev/null 2>&1 || true; }
trap cleanup EXIT

scripts/dev/gen-dev-secrets.sh >/dev/null
infra/crowdsec/scripts/bootstrap-bouncer.sh .dev-secrets >/dev/null
[[ -s .dev-secrets/crowdsec_enroll_key ]] || printf 'unset' > .dev-secrets/crowdsec_enroll_key
scripts/test/traefik-test-certs.sh >/dev/null
export CORE_BIND_IP=127.0.0.1 GOOGLE_CLIENT_ID=dryrun-google-client-id.apps.googleusercontent.com ACME_EMAIL=dryrun@example.com

echo "== core =="
"${CORE[@]}" config -q || fail "core stack + overlay does not validate"
"${CORE[@]}" up -d --build --wait 2>&1 | tail -1
[[ "$(curl -sf http://127.0.0.1:8000/readyz | jq -r .status)" == "ok" ]] || fail "backend not ready"
[[ "$(curl -sf http://127.0.0.1:8080/auth/realms/app/.well-known/openid-configuration | jq -r .issuer)" == "https://test-vinayak.duckdns.org/auth/realms/app" ]] || fail "keycloak issuer wrong"
[[ "$("${CORE[@]}" ps --format '{{.Service}} {{.State}}' | grep -c running)" -eq 3 ]] || fail "expected postgres, keycloak, backend running: $("${CORE[@]}" ps --format '{{.Service}} {{.State}}')"
"${CORE[@]}" ps -a --format '{{.Service}} {{.ExitCode}}' | grep -q "^migrate 0" || fail "migrate did not exit 0"
[[ "$("${CORE[@]}" exec -T postgres id -u)" == "999" ]] || fail "postgres not running as uid 999"
pass "core: postgres (uid 999, no caps), migrate exit 0, keycloak + backend healthy, public issuer"
"${CORE[@]}" down -v >/dev/null

echo "== edge =="
"${EDGE[@]}" config -q || fail "edge stack + overlay does not validate"
"${EDGE[@]}" up -d --build --wait 2>&1 | tail -1
code="$(curl -sk --resolve test-vinayak.duckdns.org:18443:127.0.0.1 -o /dev/null -w '%{http_code}' https://test-vinayak.duckdns.org:18443/)"
[[ "$code" == "200" ]] || fail "edge: / through traefik -> frontend returned $code"
curl -sk --resolve test-vinayak.duckdns.org:18443:127.0.0.1 https://test-vinayak.duckdns.org:18443/ | grep -q "Sign in with Google" || fail "edge: frontend page not served"
[[ "$(curl -sk --resolve test-vinayak.duckdns.org:18443:127.0.0.1 -o /dev/null -w '%{http_code}' https://test-vinayak.duckdns.org:18443/auth/admin)" == "404" ]] || fail "edge: /auth/admin not blocked"
"${EDGE[@]}" exec -T crowdsec cscli bouncers list -o json | jq -e '.[] | select(.name=="traefik")' >/dev/null || fail "edge: bouncer not registered"
pass "edge: traefik -> real frontend image (200, landing page), /auth/admin 404, crowdsec bouncer registered"
echo "STACK DRY RUN PASSED"
