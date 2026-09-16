#!/usr/bin/env bash
# Smoke test for the local stack (PLAN T09): health endpoints, discovery, landing page, then a full
# sign-in/sign-out with a local Keycloak user (created here if missing) via scripts/test/frontend-e2e.sh.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SECRETS="$ROOT/.dev-secrets"
KC="http://localhost:8080/auth"
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok: $*"; }

wait_for() { local url="$1" n="${2:-60}"; for _ in $(seq 1 "$n"); do curl -sf "$url" >/dev/null 2>&1 && return 0; sleep 2; done; return 1; }

wait_for http://localhost:8000/healthz || fail "backend /healthz not answering"
[[ "$(curl -sf http://localhost:8000/readyz | jq -r .status)" == "ok" ]] || fail "backend /readyz not ok"
pass "backend healthy and ready (database reachable)"
[[ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8000/docs)" == "200" ]] || fail "backend /docs should be on in the local environment"
pass "backend OpenAPI docs enabled locally"

wait_for "$KC/realms/app/.well-known/openid-configuration" || fail "Keycloak discovery not served"
[[ "$(curl -sf "$KC/realms/app/.well-known/openid-configuration" | jq -r .issuer)" == "$KC/realms/app" ]] || fail "unexpected issuer"
pass "Keycloak realm app served at $KC"

wait_for http://localhost:3000/api/healthz || fail "frontend not answering"
curl -sf http://localhost:3000/ | grep -q "Sign in with Google" || fail "landing page missing sign-in button"
pass "frontend landing page renders"

# local dev user (idempotent), then the browser-less end-to-end flow
admin_pw="$(cat "$SECRETS/keycloak_admin_password")"
dev_pw="$(cat "$SECRETS/dev_user_password")"
tok="$(curl -sf -X POST "$KC/realms/master/protocol/openid-connect/token" -d grant_type=password -d client_id=admin-cli -d username=admin --data-urlencode "password=$admin_pw" | jq -r .access_token)"
[[ -n "$tok" && "$tok" != "null" ]] || fail "admin login failed"
code="$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $tok" -H 'Content-Type: application/json' -X POST "$KC/admin/realms/app/users" -d "$(jq -n --arg pw "$dev_pw" '{username:"dev@example.com",email:"dev@example.com",emailVerified:true,enabled:true,firstName:"Dev",lastName:"User",credentials:[{type:"password",value:$pw,temporary:false}]}')")"
[[ "$code" == "201" || "$code" == "409" ]] || fail "creating dev user failed (HTTP $code)"
pass "local user dev@example.com present (password in .dev-secrets/dev_user_password)"

E2E_USER=dev@example.com E2E_PASSWORD="$dev_pw" E2E_NAME="Dev User" \
  "$ROOT/scripts/test/frontend-e2e.sh" http://localhost:3000 "$KC/realms/app"

echo "LOCAL STACK SMOKE PASSED — open http://localhost:3000 and sign in as dev@example.com"
