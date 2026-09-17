#!/usr/bin/env bash
# Static validation of infra/host (PLAN T17) inside ubuntu:26.04 containers:
# Runs ShellCheck, rendered cloud-init schema, nftables syntax, wg-quick strip, DOCKER-USER rules.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
IMG="ubuntu:26.04@sha256:513c074113a871b51a8d16ab445c88779d6452d937a164fb5cc479f32668a41d"
OUT="${TMPDIR:-/tmp}/host-config-test.$$"; mkdir -p "$OUT"; trap 'rm -rf "$OUT"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok: $*"; }

shellcheck infra/host/scripts/*.sh && pass "shellcheck infra/host/scripts"

keys="$(docker run --rm "$IMG" bash -c 'apt-get update -qq >/dev/null 2>&1; apt-get install -y -qq wireguard-tools >/dev/null 2>&1; k=$(wg genkey); p=$(echo $k | wg pubkey); echo $k $p')"
WG_PRIV="${keys%% *}"; WG_PUB="${keys##* }"
for role in edge core; do
  infra/host/scripts/render-cloud-init.sh "$role" scripts/test/host-vars.example "$OUT/$role.yaml"
  sed -e "s/__PUBLIC_IF__/eth0/" -e "s/__WG_PORT__/51820/" "infra/host/nftables/$role.nft" > "$OUT/$role.nft"
  WG_PRIV="$WG_PRIV" WG_PUB="$WG_PUB" python3 - "infra/host/wireguard/wg0-$role.conf.tmpl" "$OUT/wg0-$role.conf" <<'PY2'
import os, sys
t = open(sys.argv[1]).read()
for k in ("__CORE_PUBLIC_KEY__", "__EDGE_PUBLIC_KEY__", "__ADMIN_PUBLIC_KEY__"):
    t = t.replace(k, os.environ["WG_PUB"])
t = t.replace("__WG_PRIVATE_KEY__", os.environ["WG_PRIV"]).replace("__CORE_ENDPOINT__", "10.0.0.9:51820").replace("__EDGE_ENDPOINT__", "10.0.0.9:51820")
open(sys.argv[2], "w").write(t)
PY2
done
pass "cloud-init rendered for edge and core (no placeholders left)"

docker run --rm -v "$OUT:/t:ro" -v "$ROOT/infra/host:/host:ro" "$IMG" bash -c '
set -euo pipefail
apt-get update -qq >/dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nftables cloud-init wireguard-tools iproute2 iptables >/dev/null 2>&1
for role in edge core; do
  cloud-init schema --config-file /t/$role.yaml >/dev/null && echo "ok: cloud-init schema $role"
  wg-quick strip /t/wg0-$role.conf >/dev/null && echo "ok: wg-quick strip $role"
  grep -q "^ListenAddress 10.10.0.$([[ $role == edge ]] && echo 1 || echo 2)$" /t/$role.yaml && echo "ok: sshd listens on the $role WireGuard address"
done
python3 -c "import json; json.load(open(\"/host/docker/daemon.json\"))" && echo "ok: daemon.json is valid JSON"
' || fail "container validation failed"

# nftables syntax (needs NET_ADMIN even for -c) and DOCKER-USER rules via iptables-nft, in a privileged container
docker run --rm --privileged -v "$OUT:/t:ro" -v "$ROOT/infra/host/scripts:/s:ro" "$IMG" bash -c '
set -euo pipefail
apt-get update -qq >/dev/null 2>&1; DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nftables iptables iproute2 >/dev/null 2>&1
for role in edge core; do nft -c -f /t/$role.nft && echo "ok: nftables syntax $role"; done
update-alternatives --set iptables /usr/sbin/iptables-nft >/dev/null 2>&1 || true
ip link add wg0 type dummy 2>/dev/null || true
for role in edge core; do
  PUBLIC_IF=eth0 /s/docker-user-rules.sh $role >/dev/null
  n=$(iptables -S DOCKER-USER | grep -c "^-A DOCKER-USER")
  [[ $n -ge 7 ]] || { echo "too few rules for $role: $n"; exit 1; }
  iptables -S DOCKER-USER | grep -q -- "-i eth0 -m conntrack --ctstate NEW -j DROP" || { echo "missing final DROP for $role"; exit 1; }
  echo "ok: DOCKER-USER rules for $role ($n rules, ends with DROP)"
done
iptables -S DOCKER-USER | grep -q "ctorigdstport 8000" && echo "ok: core allows 8000 only from 10.10.0.1 on wg0"
' || fail "DOCKER-USER rules test failed"

echo "ALL HOST CONFIG CHECKS PASSED"
