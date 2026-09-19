#!/usr/bin/env bash
# Tests for the T20 host bootstrap pieces (PLAN T20, ADR-0026): render-time validation of the host
# variables, the rendered cloud-init (no tunnel config, key-only public SSH, private-network peer),
# public-interface detection and the boot report. Runs in ubuntu:26.04 containers like host-config.sh.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
IMG="ubuntu:26.04@sha256:513c074113a871b51a8d16ab445c88779d6452d937a164fb5cc479f32668a41d"
OUT="${TMPDIR:-/tmp}/host-bootstrap-test.$$"; mkdir -p "$OUT"
# files written by the (root) container are chowned back before cleanup; never fail the run on cleanup
trap 'rm -rf "$OUT" 2>/dev/null || true' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok: $*"; }
R=infra/host/scripts/render-cloud-init.sh

shellcheck infra/host/scripts/*.sh && pass "shellcheck infra/host/scripts"

# 1. Render refuses malformed private addresses and SSH source CIDRs (a bad value would lock the admin out).
bad() { # <description> <sed expression or extra line>
  sed "$2" scripts/test/host-vars.example > "$OUT/bad.vars"
  ! $R edge "$OUT/bad.vars" "$OUT/bad.yaml" 2>"$OUT/err" || fail "render accepted $1"
  grep -q "$3" "$OUT/err" || fail "render error for $1 does not name $3: $(cat "$OUT/err")"
}
bad "a non-IPv4 core address" 's/^CORE_PRIVATE_IP=.*/CORE_PRIVATE_IP=10.0.0/' CORE_PRIVATE_IP
bad "equal private addresses" 's/^EDGE_PRIVATE_IP=.*/EDGE_PRIVATE_IP=10.0.0.2/' EDGE_PRIVATE_IP
bad "a CIDR without a prefix" 's#^ADMIN_SSH_CIDRS=.*#ADMIN_SSH_CIDRS=198.51.100.7#' ADMIN_SSH_CIDRS
bad "a prefix above /32" 's#^ADMIN_SSH_CIDRS=.*#ADMIN_SSH_CIDRS=198.51.100.0/33#' ADMIN_SSH_CIDRS
bad "an IPv6 CIDR" 's#^ADMIN_SSH_CIDRS=.*#ADMIN_SSH_CIDRS=2001:db8::/32#' ADMIN_SSH_CIDRS
pass "render rejects malformed private addresses and SSH source CIDRs"

# 2. Rendered cloud-init: no pre-ADR-0026 tunnel config, no placeholder, peer address in host.env, boot report wiring.
for role in edge core; do
  $R "$role" scripts/test/host-vars.example "$OUT/$role.yaml"
  y="$(cat "$OUT/$role.yaml")"
  ! grep -qiE 'wireguard|wg0|wg-quick|10\.10\.0\.|psk' <<<"$y" || fail "$role: pre-ADR-0026 tunnel remnant in rendered cloud-init: $(grep -niE 'wireguard|wg0|wg-quick|10\.10\.0\.|psk' <<<"$y" | head -3)"
  ! grep -q '__[A-Z_]*__' <<<"$y" || fail "$role: placeholder left in rendered cloud-init"
  peer=$([[ $role == edge ]] && echo 10.0.0.2 || echo 10.0.0.11)
  grep -q "^ *PEER_IP=$peer$" <<<"$y" || fail "$role: host.env PEER_IP is not the peer private address $peer"
  grep -q 'define ADMIN_SSH_SOURCES = { 0.0.0.0/0 }' <<<"$y" || fail "$role: default SSH sources not rendered"
  grep -q 'resolve-public-if.sh' <<<"$y" || fail "$role: resolve-public-if.sh not embedded"
  last_runcmd="$(awk '/^runcmd:/{r=1; next} /^[a-z_]+:/{r=0} r && !/^[[:space:]]*(#|$)/{l=$0} END{print l}' <<<"$y")"
  [[ "$last_runcmd" == *boot-report.sh* ]] || fail "$role: boot-report.sh must be the last runcmd entry (got: $last_runcmd)"
  bootcmd="$(awk '/^bootcmd:/{b=1; next} /^[a-z_]+:/{b=0} b' <<<"$y")"
  [[ "$bootcmd" == *"boot-report.sh --loop"* ]] || fail "$role: bootcmd must start the boot-report loop"
done
grep -q '"127.0.0.1:9443:9443"' "$OUT/core.yaml" || fail "core: Portainer Server must publish on 127.0.0.1 only"
grep -q '"10.0.0.11:9001:9001"' "$OUT/edge.yaml" || fail "edge: Portainer Agent must publish on the edge private address"
pass "rendered cloud-init has no tunnel config, sets PEER_IP, binds Portainer to loopback/private addresses"

# 3. ADMIN_SSH_CIDRS: a comma-separated list renders into the nftables set; private addresses override.
sed -e 's#^ADMIN_SSH_CIDRS=.*#ADMIN_SSH_CIDRS=198.51.100.0/24,203.0.113.7/32#' -e 's/^CORE_PRIVATE_IP=.*/CORE_PRIVATE_IP=10.0.0.3/' scripts/test/host-vars.example > "$OUT/cidr.vars"
$R edge "$OUT/cidr.vars" "$OUT/edge-cidr.yaml"
grep -q 'define ADMIN_SSH_SOURCES = { 198.51.100.0/24, 203.0.113.7/32 }' "$OUT/edge-cidr.yaml" || fail "ADMIN_SSH_CIDRS list not rendered: $(grep -n ADMIN_SSH_SOURCES "$OUT/edge-cidr.yaml")"
grep -q '^ *PEER_IP=10.0.0.3$' "$OUT/edge-cidr.yaml" || fail "CORE_PRIVATE_IP override not applied"
pass "ADMIN_SSH_CIDRS and private-address overrides render"

# 4. PUBLIC_IF=auto renders and is resolved on the host before nftables starts.
sed 's/^PUBLIC_IF=.*/PUBLIC_IF=auto/' scripts/test/host-vars.example > "$OUT/auto.vars"
$R edge "$OUT/auto.vars" "$OUT/edge-auto.yaml"
grep -q 'define PUBLIC_IF = "auto"' "$OUT/edge-auto.yaml" || fail "PUBLIC_IF=auto not rendered into nftables.conf"
awk '/^runcmd:/{r=1} r && /resolve-public-if/{print NR; exit}' "$OUT/edge-auto.yaml" > "$OUT/l1"
awk '/^runcmd:/{r=1} r && /enable --now nftables/{print NR; exit}' "$OUT/edge-auto.yaml" > "$OUT/l2"
[ -s "$OUT/l1" ] && [ "$(cat "$OUT/l1")" -lt "$(cat "$OUT/l2")" ] || fail "resolve-public-if.sh must run in runcmd before nftables is enabled"
sed -e 's/__PUBLIC_IF__/auto/' -e 's#__ADMIN_SSH_CIDRS__#0.0.0.0/0#' infra/host/nftables/edge.nft > "$OUT/edge-auto.nft"
printf 'HOST_ROLE=edge\nPUBLIC_IF=auto\n' > "$OUT/host.env"

# 5. Boot report and resolver, in a container.
docker run --rm -v "$OUT:/t" -v "$ROOT/infra/host/scripts:/s:ro" -e "HOST_UID=$(id -u)" "$IMG" bash -c '
set -euo pipefail
trap "chown -R \"$HOST_UID\" /t" EXIT
apt-get update -qq >/dev/null 2>&1; DEBIAN_FRONTEND=noninteractive apt-get install -y -qq iproute2 nftables >/dev/null 2>&1
# boot report: runs without nft/cloud-init/sshd present, prints every section, never fails
BOOT_REPORT_OUT=/t/boot-report.txt BOOT_REPORT_LOG=/t/boot-report.log /s/boot-report.sh
grep -q "busy:" /t/boot-report.txt && grep -q "cloud-init-output tail:" /t/boot-report.txt || { echo "report misses the activity sections"; exit 1; }
grep -q "sshd:" /t/boot-report.txt && grep -q "peer (private network):" /t/boot-report.txt || { echo "report misses the sshd/peer sections"; exit 1; }
! grep -qi "wg-quick\|wireguard" /t/boot-report.txt || { echo "boot report still mentions the removed tunnel"; exit 1; }
# --loop exits immediately when cloud-init reports done (stub), after one report
mkdir -p /t/bin && printf "#!/bin/sh\necho status: done\n" > /t/bin/cloud-init && chmod +x /t/bin/cloud-init
PATH=/t/bin:$PATH BOOT_REPORT_OUT=/t/loop.txt BOOT_REPORT_LOG=/t/loop.log timeout 20 /s/boot-report.sh --loop || { echo "loop did not exit on done"; exit 1; }
[ "$(grep -c "end boot report" /t/loop.log)" = 1 ] || { echo "loop wrote $(grep -c "end boot report" /t/loop.log) reports, expected 1"; exit 1; }
echo "ok: boot-report.sh --loop reports once and stops when cloud-init is done"
grep -q "boot report" /t/boot-report.txt && grep -q "end boot report" /t/boot-report.log || { echo "summary missing from the console target or the log"; exit 1; }
echo "ok: boot-report.sh prints the summary to the console target and the log"
# resolver: default route interface replaces "auto" in nftables.conf and host.env
/s/resolve-public-if.sh /t/edge-auto.nft /t/host.env
ifc=$(ip -o -4 route show default | awk "{print \$5}" | head -1)
grep -q "define PUBLIC_IF = \"$ifc\"" /t/edge-auto.nft && grep -q "^PUBLIC_IF=$ifc$" /t/host.env || { echo "resolver did not substitute $ifc"; cat /t/host.env; exit 1; }
/s/resolve-public-if.sh /t/edge-auto.nft /t/host.env && echo "ok: resolve-public-if.sh substitutes the default-route interface (idempotent)"
' || fail "container checks failed"

echo "ALL HOST BOOTSTRAP CHECKS PASSED"
