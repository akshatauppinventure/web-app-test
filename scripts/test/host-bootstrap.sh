#!/usr/bin/env bash
# Tests for the T20 host bootstrap pieces (PLAN T20, T17 follow-up): render-time WireGuard bootstrap
# keys, key rotation on the host, public-interface detection, laptop config rendering and the
# finalize script (dry run with a stub ssh). Runs in ubuntu:26.04 containers like host-config.sh.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
IMG="ubuntu:26.04@sha256:513c074113a871b51a8d16ab445c88779d6452d937a164fb5cc479f32668a41d"
OUT="${TMPDIR:-/tmp}/host-bootstrap-test.$$"; mkdir -p "$OUT"
# files written by the (root) container are chowned back before cleanup; never fail the run on cleanup
trap 'rm -rf "$OUT" 2>/dev/null || true' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok: $*"; }
R=infra/host/scripts/render-cloud-init.sh

shellcheck scripts/host/*.sh infra/host/scripts/*.sh && pass "shellcheck scripts/host + infra/host/scripts"

# 1. Render refuses placeholder or malformed WireGuard keys (they would brick the host at first boot).
sed 's/^CORE_PUBLIC_KEY=.*/CORE_PUBLIC_KEY=REPLACE_AFTER_PROVISIONING/' scripts/test/host-vars.example > "$OUT/bad1.vars"
! $R edge "$OUT/bad1.vars" "$OUT/bad1.yaml" 2>"$OUT/err1" || fail "render accepted a placeholder peer key"
grep -q 'CORE_PUBLIC_KEY' "$OUT/err1" || fail "render error does not name the bad variable: $(cat "$OUT/err1")"
grep -v '^WG_PRIVATE_KEY=' scripts/test/host-vars.example > "$OUT/bad2.vars"
! $R edge "$OUT/bad2.vars" "$OUT/bad2.yaml" 2>/dev/null || fail "render accepted a vars file without WG_PRIVATE_KEY"
pass "render rejects placeholder peer keys and a missing bootstrap private key"

# 2. Rendered cloud-init carries the bootstrap private key and no placeholder at all.
for role in edge core; do
  $R "$role" scripts/test/host-vars.example "$OUT/$role.yaml"
  grep -q '__WG_PRIVATE_KEY__\|REPLACE_AFTER_PROVISIONING\|REPLACE_WITH' "$OUT/$role.yaml" && fail "$role: placeholder left in rendered cloud-init"
  grep -q "PrivateKey = $(grep '^WG_PRIVATE_KEY=' scripts/test/host-vars.example | cut -d= -f2-)" "$OUT/$role.yaml" || fail "$role: bootstrap private key not rendered"
  grep -q 'wg-rotate-key.sh' "$OUT/$role.yaml" || fail "$role: wg-rotate-key.sh not embedded"
  grep -q 'resolve-public-if.sh' "$OUT/$role.yaml" || fail "$role: resolve-public-if.sh not embedded"
  awk '/^runcmd:/{r=1} r' "$OUT/$role.yaml" | grep -q 'wg genkey' && fail "$role: runcmd still generates a key at first boot (would not match the rendered peers)"
done
pass "rendered cloud-init uses the bootstrap keys and embeds the rotate/resolve scripts"

# 3. PUBLIC_IF=auto renders and is resolved on the host before nftables starts.
sed 's/^PUBLIC_IF=.*/PUBLIC_IF=auto/' scripts/test/host-vars.example > "$OUT/auto.vars"
$R edge "$OUT/auto.vars" "$OUT/edge-auto.yaml"
grep -q 'define PUBLIC_IF = "auto"' "$OUT/edge-auto.yaml" || fail "PUBLIC_IF=auto not rendered into nftables.conf"
awk '/^runcmd:/{r=1} r && /resolve-public-if/{print NR; exit}' "$OUT/edge-auto.yaml" > "$OUT/l1"
awk '/^runcmd:/{r=1} r && /enable --now nftables/{print NR; exit}' "$OUT/edge-auto.yaml" > "$OUT/l2"
[ -s "$OUT/l1" ] && [ "$(cat "$OUT/l1")" -lt "$(cat "$OUT/l2")" ] || fail "resolve-public-if.sh must run in runcmd before nftables is enabled"
sed 's/__PUBLIC_IF__/auto/' infra/host/nftables/edge.nft > "$OUT/edge-auto.nft"
printf 'HOST_ROLE=edge\nPUBLIC_IF=auto\n' > "$OUT/host.env"

# 4. Laptop config renders from peers.yaml + outputs (fake keys), 5. rotate script, 6. resolver — all in containers.
LAPTOP_KEY="$OUT/laptop.key"; printf 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=\n' > "$LAPTOP_KEY"
python3 - "$OUT/peers.yaml" <<'PY'
import sys
open(sys.argv[1], "w").write("""network: 10.10.0.0/24
port: 51820
servers:
  edge: {wg_ip: 10.10.0.1, public_key: "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=", endpoint_for_admins: "198.51.100.10:51820"}
  core: {wg_ip: 10.10.0.2, public_key: "CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC=", endpoint_for_admins: "198.51.100.20:51820"}
admins:
  - {name: owner-laptop, wg_ip: 10.10.0.10, public_key: "DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD="}
""")
PY
scripts/host/render-laptop-wg.sh "$OUT/peers.yaml" "$LAPTOP_KEY" "$OUT/webapptest.conf" >/dev/null
{ grep -q '^Endpoint = 198.51.100.10:51820' "$OUT/webapptest.conf" && grep -q '^AllowedIPs = 10.10.0.2/32' "$OUT/webapptest.conf" \
  && grep -q '^Address = 10.10.0.10/32' "$OUT/webapptest.conf" && ! grep -q 'PresharedKey' "$OUT/webapptest.conf"; } || fail "laptop config wrong: $(cat "$OUT/webapptest.conf")"
printf 'EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE=\n' > "$OUT/psk-edge"; printf 'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF=\n' > "$OUT/psk-core"
scripts/host/render-laptop-wg.sh "$OUT/peers.yaml" "$LAPTOP_KEY" "$OUT/webapptest-psk.conf" --psk-edge "$OUT/psk-edge" --psk-core "$OUT/psk-core" >/dev/null
[ "$(grep -c '^PresharedKey = ' "$OUT/webapptest-psk.conf")" = 2 ] || fail "laptop config with PSKs wrong"
pass "laptop WireGuard config renders with and without pre-shared keys"

docker run --rm -v "$OUT:/t" -v "$ROOT/infra/host/scripts:/s:ro" -e "HOST_UID=$(id -u)" "$IMG" bash -c '
set -euo pipefail
trap "chown -R \"$HOST_UID\" /t" EXIT
apt-get update -qq >/dev/null 2>&1; DEBIAN_FRONTEND=noninteractive apt-get install -y -qq wireguard-tools iproute2 nftables >/dev/null 2>&1
wg-quick strip /t/webapptest.conf >/dev/null && wg-quick strip /t/webapptest-psk.conf >/dev/null && echo "ok: wg-quick strip laptop configs"
# rotate: conf gets a new key, public key printed matches, bootstrap template removed, no wg0 needed
mkdir -p /t/wg && k=$(wg genkey) && printf "[Interface]\nAddress = 10.10.0.1/24\nPrivateKey = %s\n[Peer]\nPublicKey = BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=\n" "$k" > /t/wg/wg0.conf && cp /t/wg/wg0.conf /t/wg/wg0.conf.tmpl
pub=$(WG_DIR=/t/wg /s/wg-rotate-key.sh wg0)
new=$(sed -n "s/^PrivateKey = //p" /t/wg/wg0.conf); [ "$new" != "$k" ] || { echo "private key not rotated"; exit 1; }
[ "$(wg pubkey <<<"$new")" = "$pub" ] || { echo "printed public key does not match the new private key"; exit 1; }
[ "$(cat /t/wg/public.key)" = "$pub" ] && [ ! -e /t/wg/wg0.conf.tmpl ] && grep -q "^PublicKey = BBBB" /t/wg/wg0.conf || { echo "rotate side effects wrong"; exit 1; }
[ "$(stat -c %a /t/wg/private.key)" = 600 ] || { echo "private.key mode $(stat -c %a /t/wg/private.key)"; exit 1; }
echo "ok: wg-rotate-key.sh rotates in place and prints the new public key"
# resolver: default route interface replaces "auto" in nftables.conf and host.env
/s/resolve-public-if.sh /t/edge-auto.nft /t/host.env
ifc=$(ip -o -4 route show default | awk "{print \$5}" | head -1)
grep -q "define PUBLIC_IF = \"$ifc\"" /t/edge-auto.nft && grep -q "^PUBLIC_IF=$ifc$" /t/host.env || { echo "resolver did not substitute $ifc"; cat /t/host.env; exit 1; }
/s/resolve-public-if.sh /t/edge-auto.nft /t/host.env && echo "ok: resolve-public-if.sh substitutes the default-route interface (idempotent)"
' || fail "container checks failed"

# 7. finalize-wireguard.sh dry run with a stub ssh/sudo/wg: rotates both hosts, updates the other peer, prints peers.yaml lines.
STUB="$OUT/stub"; mkdir -p "$STUB"
cat > "$STUB/ssh" <<'SH'
#!/usr/bin/env bash
echo "ssh $*" >> "$STUB_LOG"
case "$*" in
  *10.10.0.1*wg-rotate-key*) echo "NEWEDGEPUBKEYNEWEDGEPUBKEYNEWEDGEPUBKEYNEW1=";;
  *10.10.0.2*wg-rotate-key*) echo "NEWCOREPUBKEYNEWCOREPUBKEYNEWCOREPUBKEYNEW2=";;
  *) exit 0;;
esac
SH
cat > "$STUB/wg" <<'SH'
#!/usr/bin/env bash
echo "wg $*" >> "$STUB_LOG"; exit 0
SH
cat > "$STUB/sudo" <<'SH'
#!/usr/bin/env bash
echo "sudo $*" >> "$STUB_LOG"; "$@"
SH
chmod +x "$STUB"/*
export STUB_LOG="$OUT/stub.log"; : > "$STUB_LOG"
PATH="$STUB:$PATH" scripts/host/finalize-wireguard.sh \
  --edge-bootstrap-pub BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB= --core-bootstrap-pub CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC= \
  --laptop-conf "$OUT/webapptest.conf" --laptop-iface utun9 --edge-endpoint 198.51.100.10:51820 --core-endpoint 198.51.100.20:51820 \
  --edge-sdn 10.0.0.11:51820 --core-sdn 10.0.0.2:51820 --peers-out "$OUT/peers-snippet.yaml" --laptop-pub DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD= > "$OUT/finalize.out"
{ grep 'psk-map' "$STUB_LOG" | grep 'admin@10.10.0.1 ' | grep -q 'psk-core.*NEWCOREPUBKEYNEWCOREPUBKEYNEWCOREPUBKEYNEW2=.*DDDDDDDD' \
  && grep 'psk-map' "$STUB_LOG" | grep 'admin@10.10.0.2 ' | grep -q 'psk-edge.*NEWEDGEPUBKEYNEWEDGEPUBKEYNEWEDGEPUBKEYNEW1=.*DDDDDDDD'; } || fail "finalize did not write psk-map with the rotated keys: $(grep psk-map "$STUB_LOG")"
{ grep -q 'ssh .*admin@10.10.0.1 sudo /usr/local/sbin/wg-rotate-key.sh' "$STUB_LOG" && grep -q 'ssh .*admin@10.10.0.2 sudo /usr/local/sbin/wg-rotate-key.sh' "$STUB_LOG"; } || fail "finalize did not rotate both hosts: $(cat "$STUB_LOG")"
grep -q 'ssh .*admin@10.10.0.2 .*peer BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB= remove' "$STUB_LOG" || fail "finalize did not remove the edge bootstrap peer on core"
grep -q 'ssh .*admin@10.10.0.2 .*peer NEWEDGEPUBKEYNEWEDGEPUBKEYNEWEDGEPUBKEYNEW1= allowed-ips 10.10.0.1/32 endpoint 10.0.0.11:51820.*Endpoint = 10.0.0.11:51820' "$STUB_LOG" || fail "finalize did not add the new edge peer on core"
grep -q 'ssh .*admin@10.10.0.1 .*peer NEWCOREPUBKEYNEWCOREPUBKEYNEWCOREPUBKEYNEW2= allowed-ips 10.10.0.2/32 endpoint 10.0.0.2:51820.*Endpoint = 10.0.0.2:51820' "$STUB_LOG" || fail "finalize did not add the new core peer on edge"
{ grep -q '^PublicKey = NEWEDGEPUBKEYNEWEDGEPUBKEYNEWEDGEPUBKEYNEW1=' "$OUT/webapptest.conf" && grep -q '^PublicKey = NEWCOREPUBKEYNEWCOREPUBKEYNEWCOREPUBKEYNEW2=' "$OUT/webapptest.conf" \
  && ! grep -q 'BBBBBBBB\|CCCCCCCC' "$OUT/webapptest.conf"; } || fail "laptop config not updated with the rotated keys"
grep -q 'wg set utun9 peer BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB= remove' "$STUB_LOG" || fail "finalize did not update the live laptop tunnel"
{ grep -q 'public_key: "NEWEDGEPUBKEYNEWEDGEPUBKEYNEWEDGEPUBKEYNEW1="' "$OUT/peers-snippet.yaml" && grep -q 'public_key: "NEWCOREPUBKEYNEWCOREPUBKEYNEWCOREPUBKEYNEW2="' "$OUT/peers-snippet.yaml"; } || fail "peers snippet missing rotated keys"
# rotation order: edge rotated, laptop updated, then core — the laptop must reach core with core's (still bootstrap) key
awk '/wg-rotate-key/ && /10.10.0.1/{e=NR} /wg-rotate-key/ && /10.10.0.2/{c=NR} /wg set utun9 peer BBBB/{l=NR} END{exit !(e<l && l<c)}' "$STUB_LOG" || fail "finalize order wrong (edge rotate → laptop update → core rotate)"
pass "finalize-wireguard.sh rotates both hosts in a safe order and rewires every peer (stubbed ssh)"

echo "ALL HOST BOOTSTRAP CHECKS PASSED"
