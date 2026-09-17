#!/usr/bin/env bash
# Renders the owner laptop's WireGuard config from infra/host/wireguard/peers.yaml (ADR-0015).
# Usage: render-laptop-wg.sh <peers.yaml> <laptop-private-key-file> <out.conf>
#          [--admin owner-laptop] [--psk-edge FILE] [--psk-core FILE]
# Only 10.10.0.0/24 is routed through the tunnel; no DNS is pushed. PSK files come from
# `sops -d --extract '["wireguard_psk_owner-laptop"]' infra/secrets/<host>.sops.yaml` once pushed to the hosts.
set -euo pipefail
PEERS="${1:?peers.yaml}"; KEYFILE="${2:?laptop private key file}"; OUT="${3:?output conf}"; shift 3
ADMIN=owner-laptop; PSK_EDGE=""; PSK_CORE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --admin) ADMIN="$2"; shift 2 ;;
    --psk-edge) PSK_EDGE="$2"; shift 2 ;;
    --psk-core) PSK_CORE="$2"; shift 2 ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
done
PRIV="$(tr -d '[:space:]' < "$KEYFILE")"
[[ "$PRIV" =~ ^[A-Za-z0-9+/]{43}=$ ]] || { echo "laptop private key file is not a WireGuard key" >&2; exit 1; }
umask 077
PRIV="$PRIV" ADMIN="$ADMIN" PSK_EDGE="$PSK_EDGE" PSK_CORE="$PSK_CORE" python3 - "$PEERS" "$OUT" <<'PY'
import os, re, sys, yaml
peers, out = sys.argv[1:3]
d = yaml.safe_load(open(peers))
admin = next((a for a in d["admins"] if a["name"] == os.environ["ADMIN"]), None)
if admin is None:
    sys.exit(f"admin {os.environ['ADMIN']} not in {peers}")
key_re = re.compile(r"^[A-Za-z0-9+/]{43}=$")
lines = ["[Interface]", f"PrivateKey = {os.environ['PRIV']}", f"Address = {admin['wg_ip']}/32", ""]
for name in ("edge", "core"):
    s = d["servers"][name]
    if not key_re.match(s["public_key"]):
        sys.exit(f"{name}: public_key is not a key ({s['public_key']}); fill peers.yaml after provisioning")
    ep = s["endpoint_for_admins"]
    if "<" in ep:
        sys.exit(f"{name}: endpoint_for_admins is a placeholder ({ep})")
    lines += ["[Peer]", f"# {name}", f"PublicKey = {s['public_key']}", f"AllowedIPs = {s['wg_ip']}/32", f"Endpoint = {ep}", "PersistentKeepalive = 25"]
    psk_file = os.environ.get(f"PSK_{name.upper()}")
    if psk_file:
        psk = open(psk_file).read().strip()
        if not key_re.match(psk):
            sys.exit(f"{psk_file} is not a WireGuard pre-shared key")
        lines.append(f"PresharedKey = {psk}")
    lines.append("")
open(out, "w").write("\n".join(lines))
PY
chmod 600 "$OUT"
echo "wrote $OUT ($(grep -c '^\[Peer\]' "$OUT") peers, $(grep -c '^PresharedKey' "$OUT" || true) pre-shared keys)"
