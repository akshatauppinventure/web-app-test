#!/usr/bin/env bash
# Static validation of infra/host (PLAN T17) inside ubuntu:26.04 containers:
# Runs ShellCheck, rendered cloud-init schema, nftables syntax (incl. the SSH rate limit), DOCKER-USER rules.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
IMG="ubuntu:26.04@sha256:513c074113a871b51a8d16ab445c88779d6452d937a164fb5cc479f32668a41d"
OUT="${TMPDIR:-/tmp}/host-config-test.$$"; mkdir -p "$OUT"; trap 'rm -rf "$OUT"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok: $*"; }

shellcheck infra/host/scripts/*.sh && pass "shellcheck infra/host/scripts"

for role in edge core; do
  infra/host/scripts/render-cloud-init.sh "$role" scripts/test/host-vars.example "$OUT/$role.yaml"
  sed -e "s/__PUBLIC_IF__/eth0/" -e "s#__ADMIN_SSH_CIDRS__#198.51.100.0/24, 203.0.113.7/32#" "infra/host/nftables/$role.nft" > "$OUT/$role.nft"
  sed -e "s/__PUBLIC_IF__/eth0/" -e "s#__ADMIN_SSH_CIDRS__#0.0.0.0/0#" "infra/host/nftables/$role.nft" > "$OUT/$role-default.nft"
done
pass "cloud-init rendered for edge and core (no placeholders left)"

docker run --rm -v "$OUT:/t:ro" -v "$ROOT/infra/host:/host:ro" "$IMG" bash -c '
set -euo pipefail
apt-get update -qq >/dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nftables cloud-init iproute2 iptables >/dev/null 2>&1
for role in edge core; do
  cloud-init schema --config-file /t/$role.yaml >/dev/null && echo "ok: cloud-init schema $role"
  ! grep -qE "^ *ListenAddress" /t/$role.yaml || { echo "sshd must not be bound to one address on $role (ADR-0026)"; exit 1; }
  grep -qE "^ *PasswordAuthentication no$" /t/$role.yaml && grep -qE "^ *AllowUsers admin$" /t/$role.yaml || { echo "sshd hardening missing on $role"; exit 1; }
  echo "ok: $role sshd listens on all addresses, keys only, admin only"
done
python3 -c "import json; json.load(open(\"/host/docker/daemon.json\"))" && echo "ok: daemon.json is valid JSON"
' || fail "container validation failed"

# nftables syntax (needs NET_ADMIN even for -c) and DOCKER-USER rules via iptables-nft, in a privileged container
docker run --rm --privileged -v "$OUT:/t:ro" -v "$ROOT/infra/host/scripts:/s:ro" "$IMG" bash -c '
set -euo pipefail
apt-get update -qq >/dev/null 2>&1; DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nftables iptables iproute2 >/dev/null 2>&1
for role in edge core; do
  nft -c -f /t/$role.nft && nft -c -f /t/$role-default.nft && echo "ok: nftables syntax $role (allowlist and default 0.0.0.0/0)"
  grep -q "ip saddr \$ADMIN_SSH_SOURCES tcp dport 22 ct state new add @ssh_rate" /t/$role.nft || { echo "SSH rule missing on $role"; exit 1; }
  ! grep -qiE "wg0|udp dport" /t/$role.nft || { echo "$role nftables still opens a WireGuard/UDP port"; exit 1; }
done
echo "ok: nftables accept SSH only from ADMIN_SSH_SOURCES with a per-source rate limit, no UDP service ports"
update-alternatives --set iptables /usr/sbin/iptables-nft >/dev/null 2>&1 || true
for role in edge core; do
  peer=$([[ $role == edge ]] && echo 10.0.0.2 || echo 10.0.0.11)
  PUBLIC_IF=eth0 PEER_IP=$peer /s/docker-user-rules.sh $role >/dev/null
  rules="$(iptables -S DOCKER-USER)"   # captured once: grep -q on a pipe can SIGPIPE under pipefail
  n=$(grep -c "^-A DOCKER-USER" <<<"$rules")
  [[ $n -ge 7 ]] || { echo "too few rules for $role: $n"; exit 1; }
  grep -q -- "-i eth0 -m conntrack --ctstate NEW -j DROP" <<<"$rules" || { echo "missing public DROP for $role"; exit 1; }
  grep -qx -- "-A DOCKER-USER -m conntrack --ctstate NEW -j DROP" <<<"$rules" || { echo "missing final DROP for $role"; exit 1; }
  ! grep -q "wg0\|10.10.0" <<<"$rules" || { echo "$role still references WireGuard"; exit 1; }
  echo "ok: DOCKER-USER rules for $role ($n rules, ends with DROP)"
done
grep -qE -- "-s 10.0.0.11/32 ! -i eth0 -p tcp .*--ctorigdstport 8000 -j RETURN" <<<"$rules" \
  || { echo "core must allow 8000 only from the edge private address, not via eth0"; echo "$rules"; exit 1; }
echo "ok: core allows 8000 only from 10.0.0.11 and never via the public interface"
! PUBLIC_IF=eth0 /s/docker-user-rules.sh core >/dev/null 2>&1 || { echo "rules applied without PEER_IP"; exit 1; }
echo "ok: docker-user-rules.sh refuses to run without PEER_IP"
' || fail "DOCKER-USER rules test failed"

echo "ALL HOST CONFIG CHECKS PASSED"
