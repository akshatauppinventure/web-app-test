#!/usr/bin/env bash
# Traefik routing, blocking, header, size and rate-limit checks (PLAN T14; ADR-0012).
# Usage: traefik-routes.sh [https-port] [http-port] [host]
set -euo pipefail
HTTPS_PORT="${1:-18443}"
HTTP_PORT="${2:-18081}"
HOST="${3:-test-vinayak.duckdns.org}"
BASE="https://$HOST:$HTTPS_PORT"
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok: $*"; }
# --resolve pins the public hostname to loopback; -k because the test has no real certificate.
c() { curl -sk --resolve "$HOST:$HTTPS_PORT:127.0.0.1" --resolve "$HOST:$HTTP_PORT:127.0.0.1" "$@"; }
code() { c -o /dev/null -w '%{http_code}' "$@"; }

for _ in $(seq 1 30); do [[ "$(code "$BASE/" || true)" == "200" ]] && break; sleep 1; done

[[ "$(code "$BASE/")" == "200" ]] || fail "/ should be 200 from the frontend"
c "$BASE/" | grep -q "frontend-stub" || fail "/ was not served by the frontend upstream"
pass "/ -> 200 from frontend"

[[ "$(code "$BASE/auth/realms/app/.well-known/openid-configuration")" == "200" ]] || fail "realm discovery path should reach Keycloak"
c "$BASE/auth/realms/app/.well-known/openid-configuration" | grep -q "keycloak-stub" || fail "realm path not served by the keycloak upstream"
[[ "$(code "$BASE/auth/resources/abc/login/keycloak/css/login.css")" == "200" ]] || fail "/auth/resources/ should reach Keycloak"
pass "/auth/realms/* and /auth/resources/* -> Keycloak"

for p in /auth /auth/ /auth/admin /auth/admin/ /auth/admin/master/console /auth/admin/master/console/ /auth/metrics /auth/health /auth/realms /auth/../auth/admin; do
  s="$(code "$BASE$p")"
  [[ "$s" == "404" ]] || fail "$p should be 404, got $s"
  c "$BASE$p" | grep -q "keycloak-stub" && fail "$p reached the keycloak upstream" || true
done
[[ "$(code "$BASE/auth/realms/master/protocol/openid-connect/auth")" == "200" ]] || fail "master realm public path unexpectedly blocked (admin login must still work over WireGuard only)"
pass "Keycloak admin/console/metrics/health paths -> 404, never proxied"

[[ "$(code -H "Host: other.example" "$BASE/")" == "404" ]] || fail "unknown Host header should be 404"
# the 404 body is the frontend's not-found page (errors middleware -> /__not_found__), never the request itself
c -H "Host: other.example" "$BASE/" | grep -q "__not_found__" || fail "unknown Host 404 did not come from the not-found handler"
if curl -sk -o /dev/null "https://127.0.0.1:$HTTPS_PORT/" 2>/dev/null; then fail "TLS handshake without a known SNI should be refused (sniStrict)"; fi
if curl -sk -o /dev/null --resolve "other.example:$HTTPS_PORT:127.0.0.1" "https://other.example:$HTTPS_PORT/" 2>/dev/null; then fail "TLS handshake with an unknown SNI should be refused (sniStrict)"; fi
pass "unknown Host -> 404; IP / unknown SNI -> TLS refused (sniStrict)"

hdrs="$(c -D - -o /dev/null "$BASE/" | tr -d '\r' | tr '[:upper:]' '[:lower:]')"
grep -q "^strict-transport-security: max-age=63072000; includesubdomains" <<<"$hdrs" || fail "HSTS missing: $hdrs"
grep -q "^x-content-type-options: nosniff" <<<"$hdrs" || fail "nosniff missing"
grep -q "^x-frame-options: deny" <<<"$hdrs" || fail "frame deny missing"
grep -q "^referrer-policy: strict-origin-when-cross-origin" <<<"$hdrs" || fail "referrer policy missing"
grep -q "^permissions-policy: " <<<"$hdrs" || fail "permissions policy missing"
grep -q "^server:" <<<"$hdrs" && fail "Server header present" || true
grep -q "^x-powered-by:" <<<"$hdrs" && fail "X-Powered-By header present" || true
pass "security headers present; no Server / X-Powered-By"

hdrs404="$(c -D - -o /dev/null "$BASE/auth/admin" | tr -d '\r' | tr '[:upper:]' '[:lower:]')"
grep -q "^strict-transport-security" <<<"$hdrs404" || fail "HSTS missing on 404 responses"
pass "security headers also on blocked paths"

loc="$(c -o /dev/null -w '%{http_code} %{redirect_url}' "http://$HOST:$HTTP_PORT/some/path?q=1")"
[[ "$loc" == "301 https://$HOST/some/path?q=1" || "$loc" == "308 https://$HOST/some/path?q=1" ]] || fail "http should redirect permanently to https://$HOST (public port): $loc"
pass "http -> https permanent redirect"

bodydir="$(mktemp -d)"; trap 'rm -rf "$bodydir"' EXIT
head -c 2097152 /dev/zero | tr '\0' 'a' > "$bodydir/2mib"
head -c 300000 /dev/zero | tr '\0' 'a' > "$bodydir/300k"
s="$(c -o /dev/null -w '%{http_code}' -X POST --data-binary "@$bodydir/2mib" "$BASE/")"
[[ "$s" == "413" ]] || fail "2 MiB POST should be 413, got $s"
s="$(c -o /dev/null -w '%{http_code}' -X POST --data-binary "@$bodydir/300k" "$BASE/auth/realms/app/protocol/openid-connect/token")"
[[ "$s" == "413" ]] || fail "300 KiB POST to /auth should be 413, got $s"
s="$(c -o /dev/null -w '%{http_code}' -X POST --data-binary "@$bodydir/300k" "$BASE/")"
[[ "$s" == "200" ]] || fail "300 KiB POST to the app should pass (1 MiB limit), got $s"
pass "request body limits enforced (1 MiB app, 256 KiB auth)"

codes="$(for _ in $(seq 1 200); do code "$BASE/auth/realms/app/x" & done; wait)"
n429="$(grep -c 429 <<<"$codes" || true)"
[[ "$n429" -gt 0 ]] || fail "burst of 200 requests to /auth produced no 429"
pass "rate limiting: $n429/200 burst requests got 429 on /auth"

[[ "$(c "$BASE/ping")" == "OK" ]] && fail "Traefik's ping handler answered on the public entry point" || true
pass "ping entry point not exposed publicly (/ping is just proxied like any path)"

s="$(code "$BASE/auth/realms%2Fapp/../admin")"
[[ "$s" == "400" || "$s" == "404" ]] || fail "encoded slash in path should be rejected, got $s"
s="$(code -H "X_Forwarded_For: 1.2.3.4" "$BASE/")"
[[ "$s" == "400" ]] || fail "aliased header name should be rejected (400), got $s"
pass "encoded separators and aliased header names rejected"

echo "ALL TRAEFIK ROUTE CHECKS PASSED"
