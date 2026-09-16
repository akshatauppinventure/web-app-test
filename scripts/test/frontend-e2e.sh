#!/usr/bin/env bash
# Browser-less end-to-end login through the BFF (PLAN T07/T09): Auth.js sign-in -> Keycloak login
# form -> callback -> /hello (API call) -> RP-initiated logout. Needs a running frontend, backend
# and Keycloak with the CI overlay user (see infra/keycloak/scripts/smoke.sh).
# Usage: frontend-e2e.sh [frontend-url] [keycloak-issuer]
set -euo pipefail
FE="${1:-http://localhost:3000}"
ISSUER="${2:-http://localhost:18080/auth/realms/app}"
USER_EMAIL="${E2E_USER:-smoke@example.com}"
USER_PASSWORD="${E2E_PASSWORD:-correct-horse-battery-staple-42}"
JAR="$(mktemp)"; trap 'rm -f "$JAR"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok: $*"; }
c() { curl -s -b "$JAR" -c "$JAR" "$@"; }
strip_comments() { sed 's/<!--[^>]*-->//g'; }

for _ in $(seq 1 60); do curl -sf "$FE/api/healthz" >/dev/null && break; sleep 1; done
curl -sf "$FE/api/healthz" >/dev/null || fail "frontend not up at $FE"

# 0. no session endpoint, no session cookie readable
code="$(c -o /dev/null -w '%{http_code}' "$FE/api/auth/session")"
[[ "$code" == "404" ]] || fail "/api/auth/session must be 404, got $code"
pass "/api/auth/session is disabled"
code="$(c -o /dev/null -w '%{http_code}' "$FE/hello")"
[[ "$code" == "307" || "$code" == "302" ]] || fail "unauthenticated /hello should redirect, got $code"
pass "unauthenticated /hello redirects"

# 1. start sign-in (CSRF token + POST to Auth.js)
csrf="$(c "$FE/api/auth/csrf" | jq -r .csrfToken)"
[[ -n "$csrf" && "$csrf" != "null" ]] || fail "no csrf token"
auth_url="$(c -o /dev/null -w '%{redirect_url}' -X POST "$FE/api/auth/signin/keycloak" \
  -d "csrfToken=$csrf" -d "callbackUrl=$FE/hello" -H "Origin: $FE")"
[[ "$auth_url" == "$ISSUER/protocol/openid-connect/auth?"* ]] || fail "sign-in did not redirect to Keycloak: '$auth_url'"
grep -q "code_challenge_method=S256" <<<"$auth_url" || fail "PKCE S256 missing in authorization request"
grep -q "nonce=" <<<"$auth_url" || fail "nonce missing"
grep -q "state=" <<<"$auth_url" || fail "state missing"
pass "authorization request uses PKCE S256, state and nonce"

# 2. Keycloak login form
login_html="$(c "$auth_url")"
form_action="$(grep -o 'action="[^"]*"' <<<"$login_html" | head -1 | sed 's/action="//; s/"$//; s/&amp;/\&/g')"
[[ -n "$form_action" ]] || fail "no login form found"
cb_url="$(c -o /dev/null -w '%{redirect_url}' -X POST "$form_action" \
  --data-urlencode "username=$USER_EMAIL" --data-urlencode "password=$USER_PASSWORD" -d "credentialId=")"
[[ "$cb_url" == "$FE/api/auth/callback/keycloak?"* ]] || fail "Keycloak did not redirect to the callback: '$cb_url'"
pass "Keycloak login succeeded, redirecting to the callback"

# 3. callback -> session cookie
hdrs="$(c -o /dev/null -D - "$cb_url")"
grep -qi "^location: .*/hello" <<<"$hdrs" || fail "callback did not redirect to /hello: $hdrs"
grep -i "^set-cookie: .*session-token" <<<"$hdrs" | grep -qi "httponly" || fail "session cookie is not HttpOnly"
grep -i "^set-cookie: .*session-token" <<<"$hdrs" | grep -qi "samesite=lax" || fail "session cookie is not SameSite=Lax"
pass "callback set an HttpOnly SameSite=Lax session cookie"

# 4. /hello renders the API message
page="$(c "$FE/hello" | strip_comments)"
grep -q "Hello, Smoke Test" <<<"$page" || fail "/hello did not render the API message: $(head -c 400 <<<"$page")"
grep -qo "Visit count: [0-9]*" <<<"$page" || fail "no visit count"
count1="$(grep -o "Visit count: [0-9]*" <<<"$page" | grep -o '[0-9]*$')"
page2="$(c "$FE/hello" | strip_comments)"
count2="$(grep -o "Visit count: [0-9]*" <<<"$page2" | grep -o '[0-9]*$')"
[[ "$count2" -eq $((count1 + 1)) ]] || fail "visit count did not increment ($count1 -> $count2)"
pass "/hello shows the greeting; visit count increments ($count1 -> $count2)"

# 5. no token anywhere the browser can read
grep -qi "Bearer \|access_token\|eyJ" <<<"$page2" && fail "token material found in the HTML" || true
pass "no token material in the page"

# 6. logout: cross-origin POST refused, same-origin POST ends both sessions
code="$(c -o /dev/null -w '%{http_code}' -X POST "$FE/api/logout" -H "Origin: https://evil.example")"
[[ "$code" == "403" ]] || fail "cross-origin logout should be 403, got $code"
lo="$(c -o /dev/null -w '%{http_code} %{redirect_url}' -X POST "$FE/api/logout" -H "Origin: $FE")"
[[ "$lo" == "303 $ISSUER/protocol/openid-connect/logout?"* ]] || fail "logout did not redirect to Keycloak end_session: $lo"
grep -q "id_token_hint=" <<<"$lo" || fail "id_token_hint missing"
end_code="$(c -o /dev/null -w '%{http_code}' "${lo#303 }")"
[[ "$end_code" == "302" || "$end_code" == "200" ]] || fail "Keycloak end_session failed: $end_code"
code="$(c -o /dev/null -w '%{http_code}' "$FE/hello")"
[[ "$code" == "307" || "$code" == "302" ]] || fail "still signed in after logout (HTTP $code)"
pass "logout: origin check enforced, Keycloak session ended, cookie cleared"

echo "ALL FRONTEND E2E CHECKS PASSED"
