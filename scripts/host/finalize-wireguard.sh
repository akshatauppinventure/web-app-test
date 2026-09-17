#!/usr/bin/env bash
# First-contact WireGuard finalisation (PLAN T20, ADR-0015). Run on the laptop once both hosts booted
# and the laptop tunnel (bootstrap keys) is up:
#   1. edge: rotate the key on the host (wg-rotate-key.sh) → update the laptop peer live + in the conf
#   2. core: same
#   3. cross-wire: core gets edge's new key, edge gets core's new key (live `wg set` + wg0.conf)
#   4. write psk-map on both hosts (new peer keys → psk file names) and print the peers.yaml snippet
# Order matters: after edge rotates, the laptop must already know the new key before touching core.
# Usage: finalize-wireguard.sh --edge-bootstrap-pub K --core-bootstrap-pub K --laptop-conf FILE
#          --laptop-iface utunN --edge-endpoint IP:51820 --core-endpoint IP:51820 --peers-out FILE
#          [--laptop-pub K] [--admin-user admin] [--edge-sdn 10.0.0.11:51820] [--core-sdn 10.0.0.2:51820]
set -euo pipefail
ADMIN_USER="admin"; EDGE_IP=10.10.0.1; CORE_IP=10.10.0.2; EDGE_SDN=10.0.0.11:51820; CORE_SDN=10.0.0.2:51820
EDGE_OLD=""; CORE_OLD=""; LAPTOP_CONF=""; LAPTOP_IFACE=""; EDGE_EP=""; CORE_EP=""; PEERS_OUT=""; LAPTOP_PUB=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --edge-bootstrap-pub) EDGE_OLD="$2" ;; --core-bootstrap-pub) CORE_OLD="$2" ;;
    --laptop-conf) LAPTOP_CONF="$2" ;;     --laptop-iface) LAPTOP_IFACE="$2" ;;
    --edge-endpoint) EDGE_EP="$2" ;;       --core-endpoint) CORE_EP="$2" ;;
    --peers-out) PEERS_OUT="$2" ;;         --laptop-pub) LAPTOP_PUB="$2" ;;
    --admin-user) ADMIN_USER="$2" ;;       --edge-sdn) EDGE_SDN="$2" ;; --core-sdn) CORE_SDN="$2" ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac; shift 2
done
for v in EDGE_OLD CORE_OLD LAPTOP_CONF LAPTOP_IFACE EDGE_EP CORE_EP PEERS_OUT; do [[ -n "${!v}" ]] || { echo "missing --$(tr '_' '-' <<<"${v,,}")" >&2; exit 2; }; done
is_key() { [[ "$1" =~ ^[A-Za-z0-9+/]{43}=$ ]]; }
{ is_key "$EDGE_OLD" && is_key "$CORE_OLD"; } || { echo "bootstrap public keys must be WireGuard keys" >&2; exit 2; }
if [[ -z "$LAPTOP_PUB" ]]; then LAPTOP_PUB="$(sed -n 's/^PrivateKey = //p' "$LAPTOP_CONF" | head -1 | wg pubkey 2>/dev/null || true)"; fi
SSH=(ssh -o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new)

replace_in_file() { # file old new (exact line-prefix-safe replacement, portable across macOS/GNU sed)
  python3 - "$1" "$2" "$3" <<'PY'
import sys; f, old, new = sys.argv[1:4]
t = open(f).read(); assert old in t, f"{old} not found in {f}"; open(f, "w").write(t.replace(old, new))
PY
}
laptop_swap() { # role old new endpoint wg_ip
  replace_in_file "$LAPTOP_CONF" "PublicKey = $2" "PublicKey = $3"
  sudo wg set "$LAPTOP_IFACE" peer "$2" remove
  sudo wg set "$LAPTOP_IFACE" peer "$3" allowed-ips "$5/32" endpoint "$4" persistent-keepalive 25
  echo "laptop: $1 peer now $3"
}
rotate() { # host_ip -> prints new public key
  local new; new="$("${SSH[@]}" "$ADMIN_USER@$1" sudo /usr/local/sbin/wg-rotate-key.sh | tail -1)"
  is_key "$new" || { echo "rotation on $1 returned no key: '$new'" >&2; exit 1; }
  echo "$new"
}
remote_swap() { # host_ip old new peer_wg_ip peer_sdn_endpoint
  "${SSH[@]}" "$ADMIN_USER@$1" "sudo wg set wg0 peer $2 remove; sudo wg set wg0 peer $3 allowed-ips $4/32 endpoint $5 persistent-keepalive 25 && sudo sed -i -e 's|^PublicKey = $2\$|PublicKey = $3|' -e 's|^Endpoint = .*\$|Endpoint = $5|' /etc/wireguard/wg0.conf && sudo wg syncconf wg0 <(sudo wg-quick strip wg0)"
}

echo "== 1/4 edge: rotate"
EDGE_NEW="$(rotate "$EDGE_IP")"
laptop_swap edge "$EDGE_OLD" "$EDGE_NEW" "$EDGE_EP" "$EDGE_IP"
"${SSH[@]}" "$ADMIN_USER@$EDGE_IP" true && echo "edge reachable with the rotated key"
echo "== 2/4 core: rotate"
CORE_NEW="$(rotate "$CORE_IP")"
laptop_swap core "$CORE_OLD" "$CORE_NEW" "$CORE_EP" "$CORE_IP"
"${SSH[@]}" "$ADMIN_USER@$CORE_IP" true && echo "core reachable with the rotated key"
echo "== 3/4 cross-wire edge <-> core"
remote_swap "$CORE_IP" "$EDGE_OLD" "$EDGE_NEW" "$EDGE_IP" "$EDGE_SDN"
remote_swap "$EDGE_IP" "$CORE_OLD" "$CORE_NEW" "$CORE_IP" "$CORE_SDN"
echo "== 4/4 psk-map + peers.yaml"
if is_key "$LAPTOP_PUB"; then
  "${SSH[@]}" "$ADMIN_USER@$EDGE_IP" "printf '%s psk-core\n%s psk-owner-laptop\n' '$CORE_NEW' '$LAPTOP_PUB' | sudo tee /etc/wireguard/psk-map >/dev/null"
  "${SSH[@]}" "$ADMIN_USER@$CORE_IP" "printf '%s psk-edge\n%s psk-owner-laptop\n' '$EDGE_NEW' '$LAPTOP_PUB' | sudo tee /etc/wireguard/psk-map >/dev/null"
  echo "psk-map written on both hosts (PSKs apply after secrets-push + wg-quick restart)"
else
  echo "WARNING: laptop public key unknown (--laptop-pub); psk-map not written" >&2
fi
cat > "$PEERS_OUT" <<YAML
servers:
  edge:
    wg_ip: $EDGE_IP
    public_key: "$EDGE_NEW"
    endpoint_for_core: "$EDGE_SDN"
    endpoint_for_admins: "$EDGE_EP"
  core:
    wg_ip: $CORE_IP
    public_key: "$CORE_NEW"
    endpoint_for_edge: "$CORE_SDN"
    endpoint_for_admins: "$CORE_EP"
YAML
echo "peers.yaml snippet written to $PEERS_OUT; copy it into infra/host/wireguard/peers.yaml and open a PR"
echo "bootstrap keys are now dead on both hosts: delete the rendered vars/cloud-init in .tofu-rendered"
