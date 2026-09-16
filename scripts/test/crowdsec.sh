#!/usr/bin/env bash
# CrowdSec engine + Traefik bouncer checks (PLAN T15; ADR-0013). Run after `make traefik-test`.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
COMPOSE=(docker compose -f "$ROOT/compose.traefik-test.yaml")
HOST="test-vinayak.duckdns.org"; PORT=18443; BASE="https://$HOST:$PORT"
BANNED_IP="203.0.113.9"
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok: $*"; }
cscli() { "${COMPOSE[@]}" exec -T crowdsec cscli "$@"; }
c() { curl -sk --resolve "$HOST:$PORT:127.0.0.1" "$@"; }
code() { c -o /dev/null -w '%{http_code}' "$@"; }

for _ in $(seq 1 30); do cscli lapi status >/dev/null 2>&1 && break; sleep 2; done
cscli lapi status >/dev/null 2>&1 || fail "LAPI not ready"

# 1. bouncer registered from the secret file, collections and appsec config present
cscli bouncers list -o json | jq -e '.[] | select(.name=="traefik")' >/dev/null || fail "bouncer 'traefik' not registered"
pass "bouncer 'traefik' registered (from /run/secrets/bouncer_key_traefik)"
installed="$(cscli collections list -o json | jq -r '.collections[] | select(.status=="enabled") | .name')"
while read -r col; do
  [[ -z "$col" || "$col" == \#* ]] && continue
  grep -qx "$col" <<<"$installed" || fail "collection $col not installed"
done < "$ROOT/infra/crowdsec/collections.txt"
pass "all six collections installed"
cscli appsec-configs list -o json | jq -e '.["appsec-configs"][] | select(.name=="poc/appsec-detect" and (.status|startswith("enabled")))' >/dev/null || fail "poc/appsec-detect appsec config missing"
nrules="$(cscli appsec-rules list -o json | jq '[.["appsec-rules"][] | select(.status|startswith("enabled"))] | length')"
[[ "$nrules" -gt 10 ]] || fail "only $nrules appsec rules enabled"
pass "appsec config poc/appsec-detect active with $nrules rules"

# 2. allowlist for the WireGuard network is loaded as a parser whitelist
cscli parsers list -o json | jq -e '.parsers[] | select(.name=="poc/wireguard-allowlist" and (.status|startswith("enabled")))' >/dev/null || fail "wireguard allowlist parser not loaded"
pass "WireGuard allowlist parser loaded"

# 3. a manual decision is enforced by the Traefik plugin (stream mode)
[[ "$(code -H "X-Forwarded-For: $BANNED_IP" "$BASE/")" == "200" ]] || fail "pre-check: request should pass before the ban"
cscli decisions add --ip "$BANNED_IP" --duration 5m --reason "t15-test" >/dev/null
blocked=""
for _ in $(seq 1 20); do
  if [[ "$(code -H "X-Forwarded-For: $BANNED_IP" "$BASE/")" == "403" ]]; then blocked=yes; break; fi
  sleep 1
done
[[ "$blocked" == "yes" ]] || fail "banned IP was not blocked within 20 s"
[[ "$(code "$BASE/")" == "200" ]] || fail "unbanned client should still pass"
cscli decisions delete --ip "$BANNED_IP" >/dev/null
for _ in $(seq 1 20); do
  if [[ "$(code -H "X-Forwarded-For: $BANNED_IP" "$BASE/")" == "200" ]]; then break; fi
  sleep 1
done
[[ "$(code -H "X-Forwarded-For: $BANNED_IP" "$BASE/")" == "200" ]] || fail "IP still blocked after the decision was deleted"
pass "manual ban -> 403 within the stream interval, lifted after deletion"

# 4. AppSec in detection mode: a traversal attempt is logged but not blocked
appsec_processed() { cscli metrics show appsec-engine -o json 2>/dev/null | jq '[.["appsec-engine"] | .. | objects | .processed? // empty] | add // 0'; }
appsec_rule_hits() { cscli metrics show appsec-rule -o json 2>/dev/null | jq '[.["appsec-rule"] | .. | objects | .triggered? // empty] | add // 0'; }
before="$(appsec_processed)"
# probes matched by loaded rules: crowdsecurity/vpatch-env-access and crowdsecurity/appsec-generic-test
s="$(code "$BASE/.env")"
[[ "$s" == "200" || "$s" == "404" ]] || fail "/.env probe should not be blocked in phase 1 (got $s)"
s2="$(code "$BASE/crowdsec-test-NtktlJHV4TfBSK3wvlhiOBnl")"
[[ "$s2" != "403" ]] || fail "generic test probe was blocked (phase 1 must only log)"
sleep 2
after="$(appsec_processed)"
[[ "$after" -gt "$before" ]] || fail "AppSec did not process the probe (before=$before after=$after)"
hits="$(appsec_rule_hits)"
[[ "$hits" -gt 0 ]] || fail "no AppSec rule matched the traversal probes (rule metrics: $(cscli metrics show appsec-rule -o json | head -c 300))"
pass "AppSec processed the probes ($before -> $after) and matched $hits rule hit(s) without blocking (phase 1)"

# 5. fail-open: stop CrowdSec, traffic must still flow, Traefik logs the outage
"${COMPOSE[@]}" stop crowdsec >/dev/null 2>&1
sleep 4
[[ "$(code "$BASE/")" == "200" ]] || fail "traffic blocked while CrowdSec is down (fail-open expected)"
"${COMPOSE[@]}" logs --since 30s traefik 2>/dev/null | grep -qiE "crowdsecQuery:unreachable|CrowdsecBouncerTraefikPlugin.*(unreachable|error)" || fail "Traefik did not log the CrowdSec outage"
"${COMPOSE[@]}" start crowdsec >/dev/null 2>&1
for _ in $(seq 1 30); do cscli lapi status >/dev/null 2>&1 && break; sleep 2; done
pass "fail-open confirmed: site served while CrowdSec was down; outage logged by Traefik"

echo "ALL CROWDSEC CHECKS PASSED"
