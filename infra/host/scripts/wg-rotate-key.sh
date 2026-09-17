#!/usr/bin/env bash
# Replaces this host's WireGuard key pair with one generated here (ADR-0015). The bootstrap key that
# arrived in cloud-init user_data (T20) serves only until the admin's first contact. Persists the new key
# in <iface>.conf, applies it live when the interface is up, deletes the bootstrap template, prints the
# new public key. Usage: wg-rotate-key.sh [wg0]   (WG_DIR overrides /etc/wireguard for tests)
set -euo pipefail
IFACE="${1:-wg0}"; DIR="${WG_DIR:-/etc/wireguard}"; CONF="$DIR/$IFACE.conf"
[[ -f "$CONF" ]] || { echo "wg-rotate-key: $CONF not found" >&2; exit 1; }
umask 077
NEW="$(wg genkey)"; PUB="$(wg pubkey <<<"$NEW")"
TMP="$(mktemp "$DIR/.$IFACE.conf.XXXXXX")"
awk -v k="$NEW" '/^PrivateKey[[:space:]]*=/ && !done { print "PrivateKey = " k; done = 1; next } { print }' "$CONF" > "$TMP"
grep -qF "PrivateKey = $NEW" "$TMP" || { rm -f "$TMP"; echo "wg-rotate-key: no PrivateKey line in $CONF" >&2; exit 1; }
chmod 600 "$TMP" && mv "$TMP" "$CONF"
printf '%s\n' "$NEW" > "$DIR/private.key"; printf '%s\n' "$PUB" > "$DIR/public.key"
chmod 600 "$DIR/private.key"; chmod 644 "$DIR/public.key"
rm -f "$DIR/$IFACE.conf.tmpl"
if wg show "$IFACE" >/dev/null 2>&1; then wg set "$IFACE" private-key "$DIR/private.key"; fi
echo "$PUB"
