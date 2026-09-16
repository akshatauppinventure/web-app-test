#!/usr/bin/env bash
# Keycloak smoke test (PLAN T05; ADR-0010 §6). Runs against a started image + Postgres.
# Usage: smoke.sh [base-url]   (default http://localhost:18080/auth)
# Env: KC_ADMIN_USER (admin), KC_ADMIN_PASSWORD_FILE, GOOGLE_CLIENT_ID (expected value after import)
set -euo pipefail
BASE="${1:-http://localhost:18080/auth}"
ADMIN_USER="${KC_ADMIN_USER:-admin}"
ADMIN_PASSWORD="$(tr -d '\r\n' < "${KC_ADMIN_PASSWORD_FILE:?KC_ADMIN_PASSWORD_FILE required}")"
EXPECTED_GOOGLE_CLIENT_ID="${GOOGLE_CLIENT_ID:-test-google-client-id.apps.googleusercontent.com}"
HERE="$(cd "$(dirname "$0")" && pwd)"
OVERLAY="$HERE/../realms/app-realm.ci.json"
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok: $*"; }
b64url_decode() { local s="${1//-/+}"; s="${s//_//}"; case $(( ${#s} % 4 )) in 2) s="$s==";; 3) s="$s=";; esac; printf '%s' "$s" | base64 -d 2>/dev/null; }

# 1. readiness
for _ in $(seq 1 90); do
  if curl -sf "$BASE/realms/app/.well-known/openid-configuration" >/dev/null 2>&1; then break; fi
  sleep 2
done
disc="$(curl -sf "$BASE/realms/app/.well-known/openid-configuration")" || fail "discovery document not served at $BASE"
issuer="$(jq -r .issuer <<<"$disc")"
[[ "$issuer" == "$BASE/realms/app" ]] || fail "issuer is '$issuer', expected '$BASE/realms/app'"
pass "discovery document served; issuer=$issuer"

jwks_uri="$(jq -r .jwks_uri <<<"$disc")"
nkeys="$(curl -sf "$jwks_uri" | jq '.keys | length')"
[[ "$nkeys" -ge 1 ]] || fail "JWKS has no keys"
[[ "$(curl -sf "$jwks_uri" | jq -r '.keys[] | select(.use=="sig") | .alg' | grep -c RS256)" -ge 1 ]] || fail "no RS256 signing key"
pass "JWKS has $nkeys keys incl. RS256"

jq -e '.code_challenge_methods_supported | index("S256")' <<<"$disc" >/dev/null || fail "S256 PKCE not advertised"
pass "PKCE S256 advertised"

# 2. admin token (master realm, bootstrap admin) — admin console is reachable only internally
admin_token="$(curl -sf -X POST "$BASE/realms/master/protocol/openid-connect/token" \
  -d grant_type=password -d client_id=admin-cli -d "username=$ADMIN_USER" --data-urlencode "password=$ADMIN_PASSWORD" | jq -r .access_token)"
[[ -n "$admin_token" && "$admin_token" != "null" ]] || fail "could not obtain admin token"
auth=(-H "Authorization: Bearer $admin_token")
pass "admin token obtained"

# 3. realm settings
realm="$(curl -sf "${auth[@]}" "$BASE/admin/realms/app")"
for check in \
  '.bruteForceProtected == true' \
  '.registrationAllowed == true' \
  '.sslRequired == "external"' \
  '.accessTokenLifespan == 300' \
  '.ssoSessionIdleTimeout == 1800' \
  '.ssoSessionMaxLifespan == 36000' \
  '.revokeRefreshToken == true' \
  '.refreshTokenMaxReuse == 0' \
  '.eventsEnabled == true' \
  '.eventsExpiration == 604800' \
  '.adminEventsEnabled == true' \
  '(.passwordPolicy | test("length\\(12\\)"))' \
  '(.passwordPolicy | test("passwordBlacklist"))'; do
  jq -e "$check" <<<"$realm" >/dev/null || fail "realm check failed: $check"
done
pass "realm: brute force, registration, token lifetimes, refresh rotation, events, password policy"

# 4. identity providers: apple factory loaded; google enabled with substituted client id; apple disabled
curl -sf "${auth[@]}" "$BASE/admin/realms/app/identity-provider/providers/apple" >/dev/null || fail "apple identity provider factory not loaded (extension missing?)"
pass "apple identity-provider extension loaded"
idps="$(curl -sf "${auth[@]}" "$BASE/admin/realms/app/identity-provider/instances")"
jq -e '.[] | select(.alias=="google") | .enabled == true' <<<"$idps" >/dev/null || fail "google IdP not enabled"
jq -e '.[] | select(.alias=="apple") | .enabled == false' <<<"$idps" >/dev/null || fail "apple IdP should be disabled"
gcid="$(jq -r '.[] | select(.alias=="google") | .config.clientId' <<<"$idps")"
[[ "$gcid" == "$EXPECTED_GOOGLE_CLIENT_ID" ]] || fail "google clientId placeholder not substituted (got '$gcid')"
gsec="$(jq -r '.[] | select(.alias=="google") | .config.clientSecret' <<<"$idps")"
vault_ref='$''{vault.google_client_secret}'
[[ "$gsec" == "$vault_ref" || "$gsec" == "**********" ]] || fail "google clientSecret must be a vault reference, got '$gsec'"
pass "google enabled (clientId substituted, secret via vault), apple present but disabled"

# 5. clients
clients="$(curl -sf "${auth[@]}" "$BASE/admin/realms/app/clients")"
bff="$(jq '.[] | select(.clientId=="web-bff")' <<<"$clients")"
[[ -n "$bff" ]] || fail "web-bff client missing"
for check in '.publicClient == false' '.standardFlowEnabled == true' '.directAccessGrantsEnabled == false' \
  '.implicitFlowEnabled == false' '.serviceAccountsEnabled == false' \
  '.attributes["pkce.code.challenge.method"] == "S256"' \
  '(.protocolMappers[] | select(.protocolMapper=="oidc-audience-mapper") | .config["included.client.audience"]) == "api"' \
  '(.optionalClientScopes | index("offline_access")) == null'; do
  jq -e "$check" <<<"$bff" >/dev/null || fail "web-bff check failed: $check"
done
jq -e '.[] | select(.clientId=="api") | .bearerOnly == true' <<<"$clients" >/dev/null || fail "api client is not bearer-only"
bff_id="$(jq -r .id <<<"$bff")"
bff_secret="$(curl -sf "${auth[@]}" "$BASE/admin/realms/app/clients/$bff_id/client-secret" | jq -r .value)"
[[ "$bff_secret" == "$(tr -d '\r\n' < "${WEB_BFF_CLIENT_SECRET_FILE:?}")" ]] || fail "web-bff secret placeholder not substituted"
pass "web-bff confidential + PKCE S256 + audience mapper, no offline_access; api bearer-only; secret substituted"

# 6. CI overlay (partial import: ci-smoke direct-grant client), a user created like self-registration, then a real login
curl -sf "${auth[@]}" -H 'Content-Type: application/json' -X POST "$BASE/admin/realms/app/partialImport" --data-binary "@$OVERLAY" >/dev/null || fail "partial import of CI overlay failed"
code="$(curl -s -o /dev/null -w '%{http_code}' "${auth[@]}" -H 'Content-Type: application/json' -X POST "$BASE/admin/realms/app/users" -d '{
  "username": "smoke@example.com", "email": "smoke@example.com", "emailVerified": true, "enabled": true,
  "firstName": "Smoke", "lastName": "Test",
  "credentials": [{"type": "password", "value": "correct-horse-battery-staple-42", "temporary": false}]}')"
[[ "$code" == "201" || "$code" == "409" ]] || fail "creating the smoke user failed (HTTP $code)"
uid="$(curl -sf "${auth[@]}" "$BASE/admin/realms/app/users?username=smoke@example.com&exact=true" | jq -r '.[0].id')"
eff="$(curl -sf "${auth[@]}" "$BASE/admin/realms/app/users/$uid/role-mappings/realm/composite" | jq -r '[.[].name] | sort | join(",")')"
[[ ",$eff," == *",user,"* ]] || fail "new user did not receive realm role 'user' by default (effective: $eff)"
[[ ",$eff," != *",admin,"* ]] || fail "new user must not be admin by default"
pass "new user gets realm role 'user' via default-roles-app (effective: $eff)"
tok="$(curl -sf -X POST "$BASE/realms/app/protocol/openid-connect/token" \
  -d grant_type=password -d client_id=ci-smoke -d scope=openid \
  -d username=smoke@example.com --data-urlencode 'password=correct-horse-battery-staple-42')"
access="$(jq -r .access_token <<<"$tok")"
[[ -n "$access" && "$access" != "null" ]] || fail "test user login failed: $tok"
payload="$(b64url_decode "$(cut -d. -f2 <<<"$access")")"
header="$(b64url_decode "$(cut -d. -f1 <<<"$access")")"
for check in '.typ == "Bearer"' '.azp == "ci-smoke"' '(.aud | if type=="array" then index("api") != null else . == "api" end)' \
  '(.realm_access.roles | index("user")) != null' '(.exp - .iat) == 300' '(.iss | endswith("/realms/app"))' '.sub != null'; do
  jq -e "$check" <<<"$payload" >/dev/null || fail "access token check failed: $check  payload=$payload"
done
jq -e '.alg == "RS256" and .kid != null' <<<"$header" >/dev/null || fail "token header: $header"
pass "test user login: RS256, typ Bearer, aud api, realm role user, 5-minute lifetime"

refresh="$(jq -r .refresh_token <<<"$tok")"
tok2="$(curl -sf -X POST "$BASE/realms/app/protocol/openid-connect/token" -d grant_type=refresh_token -d client_id=ci-smoke -d "refresh_token=$refresh")"
jq -e '.refresh_token != null' <<<"$tok2" >/dev/null || fail "refresh failed"
[[ "$(jq -r .refresh_token <<<"$tok2")" != "$refresh" ]] || fail "refresh token was not rotated"
if curl -sf -X POST "$BASE/realms/app/protocol/openid-connect/token" -d grant_type=refresh_token -d client_id=ci-smoke -d "refresh_token=$refresh" >/dev/null 2>&1; then
  fail "reused (revoked) refresh token was accepted"
fi
pass "refresh token rotation: old token revoked after use"

# 7. password policy enforced (weak password rejected via admin API)
code="$(curl -s -o /dev/null -w '%{http_code}' "${auth[@]}" -H 'Content-Type: application/json' -X PUT \
  "$BASE/admin/realms/app/users/$uid/reset-password" -d '{"type":"password","value":"short","temporary":false}')"
[[ "$code" == "400" ]] || fail "weak password accepted (HTTP $code)"
code="$(curl -s -o /dev/null -w '%{http_code}' "${auth[@]}" -H 'Content-Type: application/json' -X PUT \
  "$BASE/admin/realms/app/users/$uid/reset-password" -d '{"type":"password","value":"password12345","temporary":false}')"
[[ "$code" == "400" ]] || fail "blocklisted password accepted (HTTP $code)"
pass "password policy rejects short and blocklisted passwords"

# 8. brute-force lockout after repeated failures (failureFactor 10)
for _ in $(seq 1 11); do
  curl -s -o /dev/null -X POST "$BASE/realms/app/protocol/openid-connect/token" -d grant_type=password -d client_id=ci-smoke -d username=smoke@example.com -d password=wrong-password-xx
done
bf="$(curl -sf "${auth[@]}" "$BASE/admin/realms/app/attack-detection/brute-force/users/$uid")"
jq -e '.disabled == true' <<<"$bf" >/dev/null || fail "user not temporarily locked after 11 failures: $bf"
pass "brute-force detection locks the account temporarily"

# 9. management/health on port 9000 is not needed publicly; confirm metrics are not on 8080
code="$(curl -s -o /dev/null -w '%{http_code}' "$BASE/metrics")"
[[ "$code" == "404" ]] || fail "metrics exposed on the HTTP port (HTTP $code)"
pass "metrics/health not served on the application port"

echo "ALL KEYCLOAK SMOKE CHECKS PASSED"
